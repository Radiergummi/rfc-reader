import ArgumentParser
import Foundation
import Logging
import RFCCorpusKit
import RFCKit

/// The revisions scanner (docs/superpowers/specs/2026-09-29-rfc-revisions-design.md):
/// lists every active, adopted draft on datatracker, reads the header of each one that
/// changed, and writes `revisions.json` for the app and `revisions-scan.json` for its
/// own next run. Requests go one at a time, with a pause between them.
struct RevisionsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "revisions",
    abstract: "Find the adopted Internet-Drafts that intend to obsolete or update an RFC."
  )

  private static let logger = Logger(command: "revisions")
  private static let pause = Duration.milliseconds(250)

  @Option(help: "The previous run's revisions-scan.json. Without it, every adopted draft is read.")
  var scan: String?

  @Option(help: "The directory to write revisions.json and revisions-scan.json into.")
  var out: String

  @Flag(help: "Publish even when more than half the RFCs are gone since the previous run.")
  var allowShrink = false

  func run() async throws {
    let startedAt = Date.now
    let previous = try scan.map {
      try RevisionScan.decode(Data(contentsOf: URL(fileURLWithPath: $0)))
    }

    let states = Datatracker.stateTable(
      try await Self.pages(from: Datatracker.statesFirstPage, as: Datatracker.StatePage.self) {
        $0.meta.next
      })
    let listed = try await Self.pages(
      from: Datatracker.draftsFirstPage, as: Datatracker.DraftPage.self
    ) {
      $0.meta.next
    }.flatMap(\.objects)
    let adopted = listed.filter { DraftStates.isAdopted($0.states(in: states)) }
    Self.logger.info(
      "listed", metadata: ["active": "\(listed.count)", "adopted": "\(adopted.count)"])

    var readings: [String: RevisionScan.Reading] = [:]
    var failures: Set<String> = []
    for draft in adopted {
      let old = previous?.drafts[draft.name]
      let work = RevisionScan.work(for: draft, previous: old)
      guard work != .none else { continue }
      do {
        let record = try Datatracker.decoder().decode(
          Datatracker.DraftRecord.self, from: try await Self.fetch(Datatracker.record(draft.name)))
        if work == .record, let reading = old?.reading {
          readings[draft.name] = try reading.refreshed(with: record)
        } else {
          let header = try await Self.header(draft)
          if !header.unreadable.isEmpty {
            Self.logger.warning(
              "unreadable relation",
              metadata: ["draft": "\(draft.name)", "value": "\(header.unreadable)"])
          }
          readings[draft.name] = try RevisionScan.Reading(
            rev: draft.rev, header: header, record: record)
        }
      } catch {
        failures.insert(draft.name)
        Self.logger.error("read failed", error: error, metadata: ["draft": "\(draft.name)"])
      }
    }
    Self.logger.info(
      "read", metadata: ["read": "\(readings.count)", "failures": "\(failures.count)"])

    let next = RevisionScan.next(
      adopted: adopted, states: states, previous: previous, readings: readings, failures: failures)
    let revisions = next.revisions(generatedAt: startedAt)
    let before = previous?.revisions(generatedAt: startedAt)
    guard RevisionScan.mayPublish(revisions, replacing: before, allowShrink: allowShrink) else {
      Self.logger.error(
        "refusing to publish: more than half the RFCs are gone",
        metadata: [
          "before": "\(before?.revisions.count ?? 0)", "after": "\(revisions.revisions.count)",
        ])
      throw ExitCode.failure
    }

    let directory = URL(fileURLWithPath: out)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try revisions.encoded().write(to: directory.appending(path: "revisions.json"), options: .atomic)
    try next.encoded().write(to: directory.appending(path: "revisions-scan.json"), options: .atomic)
    Self.logger.info(
      "done", metadata: ["rfcs": "\(revisions.revisions.count)", "drafts": "\(next.drafts.count)"])
  }

  /// The XML where the draft was submitted as XML, the text otherwise.
  private static func header(_ draft: Datatracker.ListedDraft) async throws -> DraftHeader {
    do {
      return try DraftHeader.parse(
        xml: try await fetch(Datatracker.draft(draft.name, rev: draft.rev, extension: "xml")))
    } catch PipelineError.http(404, _) {
      return DraftHeader.parse(
        text: try await fetch(Datatracker.draft(draft.name, rev: draft.rev, extension: "txt")))
    }
  }

  /// Every page, following `next` until there is none. A failure on any page fails the
  /// run: a partial listing would drop every draft on the missing pages.
  private static func pages<Page: Decodable>(
    from first: URL, as type: Page.Type, next: (Page) -> String?
  ) async throws -> [Page] {
    var pages: [Page] = []
    var url: URL? = first
    while let current = url {
      let page = try Datatracker.decoder().decode(Page.self, from: try await fetch(current))
      pages.append(page)
      url = Datatracker.next(next(page))
    }
    return pages
  }

  private static func fetch(_ url: URL) async throws -> Data {
    try await Task.sleep(for: pause)
    return try await FetchCommand.download(url)
  }
}
