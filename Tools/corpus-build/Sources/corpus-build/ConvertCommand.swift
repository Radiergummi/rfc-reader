import ArgumentParser
import Foundation
import Logging
import RFCCorpusKit
import RFCKit

struct ConvertCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "convert",
    abstract: "Convert every legacy plain-text RFC in --in to RFCXML in --out."
  )

  private static let logger = Logger(command: "convert")

  @Option(name: .customLong("in"), help: "The directory of rfcNNNN.txt files to convert.")
  var input: String

  @Option(help: "Where to write the rfcNNNN.xml files.")
  var out: String

  @Option(
    help:
      "A directory of rfcNNNN.xml corrections: an RFC 5261 patch (<diff>) applied to the converter's output, or a whole document (<rfc>) published in its place."
  )
  var overrides: String?

  @Option(help: "Where to write the per-document report.")
  var report: String?

  @Option(
    help:
      "The RFC index, for each document's title, number, authors and date, and what it obsoletes and updates."
  )
  var index: String?

  @Option(help: "Where to write what the prose test decided. Roughly doubles the run.")
  var diagnostics: String?

  @Option(
    help:
      "Where to write the blocks the prose test refused narrowly, by line range. Costs what --diagnostics does."
  )
  var boundary: String?

  @Option(help: "Validate every written file against this RELAX NG schema with xmllint.")
  var schema: String?

  @Option(
    parsing: .upToNextOption,
    help:
      "Convert only these RFC numbers from --in. Each must have its text there. Not with --report.")
  var only: [Int] = []

  /// A report from `--only` holds only the named documents. Written over the corpus
  /// report, it becomes the next full run's baseline: the schema comparison then sees
  /// only those documents as previously valid, so any other document that stopped
  /// validating goes unreported, and a comparison of `report.json` between runs shows
  /// every document it left out as new.
  func validate() throws {
    if !only.isEmpty, report != nil {
      throw ValidationError(
        "--report cannot be combined with --only: it would hold only the named documents.")
    }
  }

  /// What converting one document asks for; the same for every document in a run.
  struct Job: Sendable {
    var inDirectory: URL
    var outDirectory: URL
    var overrides: URL?
    var converter: DocumentConverter
    var schema: URL?
    var index: RFCIndex?
  }

  /// One converted document, and where it goes in the run's output.
  struct Converted: Sendable {
    var offset: Int
    var report: DocumentReport
    var prose: ProseReport?
    var boundary: BoundarySample.Sample?
  }

  func run() async throws {
    let job = Job(
      inDirectory: URL(fileURLWithPath: input),
      outDirectory: URL(fileURLWithPath: out),
      overrides: overrides.map { URL(fileURLWithPath: $0) },
      // Diagnosing re-segments every document, which roughly doubles the run. Only pay
      // it when the report is actually asked for.
      converter: DocumentConverter(
        diagnosesProse: diagnostics != nil, countsFurniture: report != nil,
        samplesBoundary: boundary != nil),
      schema: schema.map { URL(fileURLWithPath: $0) },
      index: try index.map {
        try RFCIndexParser.parse(contentsOf: URL(fileURLWithPath: $0))
      }
    )
    try FileManager.default.createDirectory(at: job.outDirectory, withIntermediateDirectories: true)
    if let schema = job.schema { try SchemaValidation.preflight(schema: schema) }
    // Read before this run overwrites it. A report from a run that did not check is no
    // baseline (`DocumentReport.validDocuments(inReport:)`).
    var previouslyValid: Set<String>?
    if job.schema != nil, let report, let data = FileManager.default.contents(atPath: report) {
      previouslyValid = DocumentReport.validDocuments(inReport: data)
    }

    let files = try ConversionPlan.files(
      in: try FileManager.default.contentsOfDirectory(atPath: job.inDirectory.path), only: only)
    Self.logger.info("converting", metadata: ["documents": "\(files.count)"])

    // Every document is independent -- its own input, its own output file, and a parse
    // that is a pure function of its text -- so they are converted across all cores.
    // Results are put back in document order before anything is written, which keeps
    // the report and the prose sample exactly what a single pass would produce.
    //
    // A document waiting on xmllint holds no thread, so the pool moves on to the next
    // conversion meanwhile; the bound is what keeps the number of xmllint processes
    // alive at once from depending on how far the parses outrun them.
    var results: [Converted] = []
    try await withThrowingTaskGroup(of: Converted.self) { group in
      var pending = files.enumerated().makeIterator()
      func startNext() {
        guard let (offset, file) = pending.next() else { return }
        group.addTask { try await Self.convert(file, offset: offset, job: job) }
      }
      for _ in 0..<ProcessInfo.processInfo.activeProcessorCount * 2 { startNext() }
      for try await result in group {
        results.append(result)
        if results.count % 500 == 0 {
          Self.logger.info(
            "progress", metadata: ["completed": "\(results.count)", "total": "\(files.count)"])
        }
        startNext()
      }
    }
    results.sort { $0.offset < $1.offset }
    let reports = results.map(\.report)
    var prose = ProseReport()
    for case let documentProse? in results.map(\.prose) {
      prose.merge(documentProse)
    }

    if let report {
      try writeJSON(reports, to: report)
    }
    if let diagnostics {
      try writeJSON(prose, to: diagnostics)
      let rejected = prose.blocks - prose.prose - prose.lists
      Self.logger.info(
        "prose",
        metadata: [
          "blocks": "\(prose.blocks)", "lists": "\(prose.lists)", "prose": "\(prose.prose)",
          "rejected": "\(rejected)", "nearMisses": "\(prose.nearMisses)",
        ])
      for (guardName, count) in prose.soleRejection.sorted(by: { $0.value > $1.value }) {
        Self.logger.info(
          "refused by one guard only", metadata: ["guard": "\(guardName)", "blocks": "\(count)"])
      }
    }
    if let boundary {
      let entries = results.flatMap { $0.boundary?.entries ?? [] }
      try writeJSON(entries, to: boundary)
      for (criterion, count) in Dictionary(grouping: entries, by: \.criterion)
        .mapValues(\.count).sorted(by: { $0.value > $1.value })
      {
        Self.logger.info(
          "on the boundary", metadata: ["criterion": "\(criterion)", "blocks": "\(count)"])
      }
      let unlocated = results.filter { ($0.boundary?.unlocated ?? 0) > 0 }
      if !unlocated.isEmpty {
        let blocks = unlocated.reduce(0) { $0 + ($1.boundary?.unlocated ?? 0) }
        let documents = unlocated.map(\.report.id).joined(separator: ", ")
        Self.logger.warning(
          "on the boundary but not found in the source",
          metadata: ["blocks": "\(blocks)", "documents": "\(documents)"])
      }
    }
    var comparison: SchemaComparison?
    if job.schema != nil { comparison = Self.logSchema(reports, previouslyValid: previouslyValid) }
    let flagged = reports.filter { !$0.warnings.isEmpty }
    Self.logger.info(
      "done",
      metadata: [
        "converted": "\(reports.count(where: { $0.skipped == nil && $0.failure == nil }))",
        "skipped": "\(reports.count(where: { $0.skipped != nil }))",
        "patched": "\(reports.count(where: { $0.override == .patch && $0.failure == nil }))",
        "snapshots": "\(reports.count(where: { $0.override == .snapshot }))",
        "withWarnings": "\(flagged.count)",
      ])
    for entry in flagged.prefix(40) {
      Self.logger.warning(
        "document has warnings",
        metadata: [
          "document": "\(entry.id)", "warnings": .array(entry.warnings.map { .string($0) }),
        ])
    }
    // Every failed override, not only the first: each is its own fix.
    let failed = reports.compactMap(\.failure)
    for failure in failed {
      Self.logger.error("override failed", metadata: ["failure": "\(failure)"])
    }
    if !failed.isEmpty {
      Self.logger.error("overrides failed", metadata: ["documents": "\(failed.count)"])
    }
    let isRegression = comparison?.isRegression ?? false
    if let comparison, isRegression {
      Self.logger.error(
        "documents stopped validating",
        metadata: ["documents": "\(comparison.stoppedValidating.count)"])
    }
    // Last, so the report is written and everything above logged before the run fails.
    if !failed.isEmpty || isRegression { throw ExitCode.failure }
  }

  /// Converts one document and writes its XML. A snapshot is published as it is, and
  /// never diagnosed; a patch is applied to the converter's output. An override that
  /// cannot be used, a patch that does not apply or a snapshot that does not parse,
  /// is recorded as the document's failure and leaves it no output.
  static func convert(_ file: String, offset: Int, job: Job) async throws -> Converted {
    let stem = String(file.dropLast(4))
    let outputURL = job.outDirectory.appending(path: "\(stem).xml")

    var patch: XMLPatch?
    // An override that cannot be used fails its document, not the run, whichever kind.
    var unusableOverride: (kind: DocumentReport.Override, failure: String)?
    if let overrideURL = job.overrides?.appending(path: "\(stem).xml"),
      FileManager.default.fileExists(atPath: overrideURL.path)
    {
      let data = try Data(contentsOf: overrideURL)
      // An override that is not XML is a patch that failed, not a run that stops.
      if XMLPatch.isPatch(data) {
        do {
          patch = try XMLPatch(parsing: data, name: "\(stem).xml")
        } catch {
          unusableOverride = (.patch, error.description)
        }
      } else {
        do {
          let document = try RFCXMLParser.parse(data)  // a snapshot must at least parse
          try data.write(to: outputURL, options: .atomic)
          var entry = DocumentReport(document: document, id: stem, override: .snapshot)
          try await checkSchema(outputURL, job: job, into: &entry)
          return Converted(offset: offset, report: entry, prose: nil)
        } catch let error as RFCXMLParser.ParseError {
          let reason = error.errorDescription ?? "\(error)"
          unusableOverride = (.snapshot, "\(stem).xml: the snapshot does not parse: \(reason)")
        }
      }
    }

    let bytes = try Data(contentsOf: job.inDirectory.appending(path: file))
    let text = LegacyTextParser.text(decoding: bytes)
    let metadata = ConversionPlan.rfcNumber(of: stem).flatMap { job.index?[$0] }
    if job.index != nil, metadata == nil {
      // The header keeps the title page's values (#218). It should not happen for a legacy RFC.
      Self.logger.warning("no index entry", metadata: ["document": "\(stem)"])
    }
    let conversion = job.converter.convert(
      text: text, stem: stem, metadata: metadata, patch: patch)
    if let unusableOverride {
      var entry = conversion.report
      entry.override = unusableOverride.kind
      entry.failure = unusableOverride.failure
      try removeStaleOutput(outputURL)
      return Converted(offset: offset, report: entry, prose: nil)
    }
    guard let xml = conversion.xml else {
      try removeStaleOutput(outputURL)
      return Converted(offset: offset, report: conversion.report, prose: nil)
    }
    try xml.write(to: outputURL, options: .atomic)
    var entry = conversion.report
    try await checkSchema(outputURL, job: job, into: &entry)
    return Converted(
      offset: offset, report: entry, prose: conversion.prose, boundary: conversion.boundary)
  }

  /// A skipped or failed document's output from an earlier run would be packed as
  /// though this one had written it.
  static func removeStaleOutput(_ url: URL) throws {
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  static func checkSchema(_ file: URL, job: Job, into entry: inout DocumentReport) async throws {
    guard let schema = job.schema else { return }
    let result = try await SchemaValidation.check(file, schema: schema)
    entry.schema = result.causes.map(\.rawValue)
    if let message = result.firstMessage { entry.warnings.append("schema: \(message)") }
  }

  /// How many documents each cause fails, and how many it is the only cause found in:
  /// at most the documents fixing that one cause alone would make valid, since a known
  /// cause can hide an unknown one (`SchemaCheck`).
  ///
  /// Then, against the report this run replaced, the documents that stopped validating,
  /// by name (`SchemaComparison`), which the run fails on.
  static func logSchema(
    _ reports: [DocumentReport], previouslyValid: Set<String>?
  ) -> SchemaComparison? {
    let checked = reports.compactMap(\.schema)
    Self.logger.info(
      "schema",
      metadata: ["validating": "\(checked.filter(\.isEmpty).count)", "checked": "\(checked.count)"])
    for cause in SchemaCheck.Cause.allCases {
      let documents = checked.filter { $0.contains(cause.rawValue) }.count
      guard documents > 0 else { continue }
      let sole = checked.filter { $0 == [cause.rawValue] }.count
      Self.logger.info(
        "schema cause",
        metadata: [
          "cause": "\(cause.rawValue)", "documents": "\(documents)", "onlyCause": "\(sole)",
        ])
    }
    guard let previouslyValid else { return nil }
    let comparison = SchemaComparison(reports: reports, previouslyValid: previouslyValid)
    Self.logger.info(
      "schema against the previous report",
      metadata: [
        "startedValidating": "\(comparison.startedValidating)",
        "stoppedValidating": "\(comparison.stoppedValidating.count)",
      ])
    for id in comparison.stoppedValidating.prefix(40) {
      Self.logger.warning("stopped validating", metadata: ["document": "\(id)"])
    }
    return comparison
  }
}
