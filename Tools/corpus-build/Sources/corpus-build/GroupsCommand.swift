import ArgumentParser
import Foundation
import Logging
import RFCCorpusKit
import RFCKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// `groups.json` (#363): every group the RFC index names, as datatracker describes it,
/// for the app's working-group card. Lists every group and every chair role, two or
/// three pages each, then looks up the name of each active group's chairs, one request
/// at a time.
struct GroupsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "groups",
    abstract: "Describe the groups the RFC index names, from datatracker."
  )

  private static let logger = Logger(command: "groups")

  @Option(help: "The directory to write groups.json into.")
  var out: String

  @Option(help: "Read the RFC index from here instead of downloading it.")
  var index: String?

  @Option(help: "The previously published groups.json, for the shrink guard.")
  var previous: String?

  @Flag(help: "Publish even when more than half the groups are gone since the previous run.")
  var allowShrink = false

  func run() async throws {
    let startedAt = Date.now
    let index = try await readIndex()
    let named = Set(index.rfcs.compactMap(\.workingGroup))

    let groups = try await DatatrackerFetch.pages(
      from: Datatracker.groupsFirstPage, as: Datatracker.GroupPage.self
    ).flatMap(\.objects)
    let roles = try await DatatrackerFetch.pages(
      from: Datatracker.chairsFirstPage, as: Datatracker.RolePage.self
    ).flatMap(\.objects)
    let chairs = GroupsFile.chairs(roles)

    var people: [String: String] = [:]
    var failures = 0
    for uri in GroupsFile.peopleToFetch(groups: groups, named: named, chairs: chairs) {
      do {
        let person = try Datatracker.decoder().decode(
          Datatracker.Person.self, from: try await DatatrackerFetch.fetch(Datatracker.person(uri)))
        people[uri] = person.name
      } catch {
        failures += 1
        Self.logger.error("person failed", error: error, metadata: ["person": "\(uri)"])
      }
    }
    Self.logger.info(
      "read",
      metadata: [
        "groups": "\(groups.count)", "named": "\(named.count)", "chairs": "\(people.count)",
        "failures": "\(failures)",
      ])

    let file = GroupsFile.build(
      groups: groups, named: named, chairs: chairs, people: people, generatedAt: startedAt)
    let before = try previous.map {
      try WorkingGroups.decode(Data(contentsOf: URL(fileURLWithPath: $0)))
    }
    guard GroupsFile.mayPublish(file, replacing: before, allowShrink: allowShrink) else {
      Self.logger.error(
        "refusing to publish: more than half the groups are gone",
        metadata: ["before": "\(before?.groups.count ?? 0)", "after": "\(file.groups.count)"])
      throw ExitCode.failure
    }

    let directory = URL(fileURLWithPath: out)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try file.encoded().write(to: directory.appending(path: "groups.json"), options: .atomic)
    Self.logger.info("done", metadata: ["groups": "\(file.groups.count)"])
  }

  private func readIndex() async throws -> RFCIndex {
    if let index {
      return try RFCIndexParser.parse(contentsOf: URL(fileURLWithPath: index))
    }
    return try await Self.client.fetchIndex()
  }

  /// The RFC Editor's client, as `fetch` makes it.
  private static let client = RFCEditorClient(
    transport: RetryingTransport(URLSessionTransport(userAgent: RetryingTransport.userAgent)))
}
