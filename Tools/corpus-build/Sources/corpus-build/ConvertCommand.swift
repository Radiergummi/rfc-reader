import ArgumentParser
import Foundation
import RFCCorpusKit
import RFCKit

struct ConvertCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "convert",
    abstract: "Convert every legacy plain-text RFC in --in to RFCXML in --out."
  )

  @Option(name: .customLong("in"), help: "The directory of rfcNNNN.txt files to convert.")
  var input: String

  @Option(help: "Where to write the rfcNNNN.xml files.")
  var out: String

  @Option(
    help: "A directory of rfcNNNN.xml files published in place of the converter's own output.")
  var overrides: String?

  @Option(help: "Where to write the per-document report.")
  var report: String?

  @Option(help: "The RFC index, for each document's title and what it obsoletes and updates.")
  var index: String?

  @Option(help: "Where to write what the prose test decided. Roughly doubles the run.")
  var diagnostics: String?

  @Option(help: "Validate every written file against this RELAX NG schema with xmllint.")
  var schema: String?

  @Option(
    parsing: .upToNextOption,
    help: "Convert only these RFC numbers from --in. Each must have its text there.")
  var only: [Int] = []

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
  }

  func run() async throws {
    let job = Job(
      inDirectory: URL(fileURLWithPath: input),
      outDirectory: URL(fileURLWithPath: out),
      overrides: overrides.map { URL(fileURLWithPath: $0) },
      // Diagnosing re-segments every document, which roughly doubles the run. Only pay
      // it when the report is actually asked for.
      converter: DocumentConverter(
        diagnosesProse: diagnostics != nil, countsFurniture: report != nil),
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
    log("converting \(files.count) documents")

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
        if results.count % 500 == 0 { log("\(results.count)/\(files.count)") }
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
      log(
        "prose: \(prose.blocks) blocks, \(prose.lists) lists, \(prose.prose) prose, \(rejected) rejected, \(prose.nearMisses) by one guard only"
      )
      for (guardName, count) in prose.soleRejection.sorted(by: { $0.value > $1.value }) {
        log("  only \(guardName): \(count)")
      }
    }
    if job.schema != nil { Self.logSchema(reports, previouslyValid: previouslyValid) }
    let flagged = reports.filter { !$0.warnings.isEmpty }
    log(
      "done: \(reports.count) converted, \(reports.filter(\.overridden).count) overridden, \(flagged.count) with warnings"
    )
    for entry in flagged.prefix(40) {
      log("  \(entry.id): \(entry.warnings.joined(separator: "; "))")
    }
  }

  /// Converts one document and writes its XML. Overridden documents are hand-corrected,
  /// so they are never diagnosed.
  static func convert(_ file: String, offset: Int, job: Job) async throws -> Converted {
    let stem = String(file.dropLast(4))
    let outputURL = job.outDirectory.appending(path: "\(stem).xml")

    if let overrides = job.overrides,
      FileManager.default.fileExists(atPath: overrides.appending(path: "\(stem).xml").path)
    {
      let data = try Data(contentsOf: overrides.appending(path: "\(stem).xml"))
      let document = try RFCXMLParser.parse(data)  // overrides must at least parse
      try data.write(to: outputURL, options: .atomic)
      var entry = DocumentReport(document: document, id: stem, overridden: true)
      try await checkSchema(outputURL, job: job, into: &entry)
      return Converted(offset: offset, report: entry, prose: nil)
    }

    let bytes = try Data(contentsOf: job.inDirectory.appending(path: file))
    let text = DocumentConverter.text(decoding: bytes)
    let metadata = ConversionPlan.rfcNumber(of: stem).flatMap { job.index?[$0] }
    let conversion = job.converter.convert(text: text, stem: stem, metadata: metadata)
    try conversion.xml.write(to: outputURL, options: .atomic)
    var entry = conversion.report
    try await checkSchema(outputURL, job: job, into: &entry)
    return Converted(offset: offset, report: entry, prose: conversion.prose)
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
  /// by name: those are the regressions, and a count that nets them against documents
  /// that started would hide them.
  static func logSchema(_ reports: [DocumentReport], previouslyValid: Set<String>?) {
    let checked = reports.compactMap(\.schema)
    log("schema: \(checked.filter(\.isEmpty).count) of \(checked.count) validate")
    for cause in SchemaCheck.Cause.allCases {
      let documents = checked.filter { $0.contains(cause.rawValue) }.count
      guard documents > 0 else { continue }
      let sole = checked.filter { $0 == [cause.rawValue] }.count
      log("  \(cause.rawValue): \(documents), the only cause found in \(sole)")
    }
    guard let previouslyValid else { return }
    let valid = reports.filter { $0.schema == [] }.map(\.id)
    let stopped = reports.filter { previouslyValid.contains($0.id) && $0.schema != [] }.map(\.id)
    let started = valid.filter { !previouslyValid.contains($0) }.count
    log(
      "schema: against the previous report, \(started) started validating and \(stopped.count) stopped"
    )
    for id in stopped.prefix(40) { log("  stopped validating: \(id)") }
  }
}
