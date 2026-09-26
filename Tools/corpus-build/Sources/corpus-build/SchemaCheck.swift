import Foundation

#if canImport(FoundationXML)
  import FoundationXML
#endif

/// Whether a converted document is RFCXML, and if it is not, why.
///
/// Validity is `xmllint --relaxng` against xml2rfc's `v3.rng`, committed beside this
/// tool with the SVG schema it includes: libxml2's own verdict, not ours. Its messages
/// are no use for saying why, though. They cascade -- one attribute the schema refuses
/// on `<section>` is hundreds of thousands of lines over the corpus, all of them about
/// elements that are fine -- so the causes are found in the document instead, by
/// looking for each mechanical way the serializer is known to leave the schema.
///
/// A document xmllint refuses and none of those checks explains is `unexplained`. That
/// is the bucket a new kind of failure lands in, and the first thing to read after a run.
/// It only sees documents with no known cause, though: a document that already has one
/// can hold a new kind of failure behind it, and the report lists the known cause
/// alone. So the causes say what a document *contains*, not everything xmllint refused,
/// and the bucket watches more of the corpus the fewer documents a known cause is in.
/// What cannot hide is a regression: a document that validated and stops is `[]` no more.
enum SchemaCheck {
  enum Cause: String, CaseIterable, Codable, Sendable {
    /// `author+` is required in the document's `<front>` and every reference's.
    case frontWithoutAuthor = "front-without-author"
    /// `anchor` and `pn` are both `xsd:ID`, so one element declaring the same value
    /// in both declares that ID twice.
    case anchorEqualsPartNumber = "anchor-equals-pn"
    /// An ID or IDREF that is not an `NCName`: `anchor="1"`.
    case idNotNCName = "id-not-ncname"
    /// `li`, `dd`, `td`, `th` and `blockquote` hold inline content or blocks, never both.
    case inlineBesideBlocks = "inline-beside-blocks"
    /// The same ID on two elements.
    case duplicateID = "duplicate-id"
    /// An `<xref>`, `<relref>` or `<displayreference>` target, or an `iprExtract`, no
    /// element declares. xmllint resolves IDREFs, so a citation that links nowhere is a
    /// schema failure too, not only a dead link.
    case danglingTarget = "dangling-target"
    /// `<references>` belongs in `<back>`, ahead of its sections, or in another
    /// `<references>` that holds no entries of its own: not in a section, not after
    /// an appendix, and not beside a list's entries.
    case misplacedReferences = "misplaced-references"
    /// `<middle>` requires a section.
    case emptyMiddle = "empty-middle"
    /// `<abstract>` holds `t`, `dl`, `ol` and `ul` only; RFC 391's has artwork.
    case blockInAbstract = "block-in-abstract"
    /// Refused by xmllint, and by none of the checks above.
    case unexplained
  }

  /// Where it failed, when it did. `firstMessage` is only read for an unexplained
  /// failure, where libxml2's first line is the one lead there is.
  struct Result: Sendable {
    var causes: [Cause]
    var firstMessage: String?
  }

  /// Fails once, before a run, with what is actually wrong, rather than every document
  /// failing with xmllint's exit status: a schema path that does not resolve from here,
  /// or no xmllint on the path (libxml2-utils, on Linux).
  static func preflight(schema: URL) throws {
    guard FileManager.default.fileExists(atPath: schema.path) else {
      throw CheckError.schemaMissing(schema.path)
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["xmllint", "--version"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CheckError.xmllintMissing }
  }

  static func check(_ file: URL, schema: URL) async throws -> Result {
    guard try await !validates(file, schema: schema) else { return Result(causes: []) }
    let found = causes(in: try Data(contentsOf: file))
    guard found.isEmpty else { return Result(causes: found) }
    return Result(
      causes: [.unexplained], firstMessage: try await firstMessage(file, schema: schema))
  }

  private static func validates(_ file: URL, schema: URL) async throws -> Bool {
    // Only the exit status is read here: a failing document can write megabytes of
    // messages, and draining them costs more than the validation itself.
    let process = xmllint(file, schema: schema)
    process.standardError = FileHandle.nullDevice
    let status = try await exitStatus(of: process)
    switch status {
    case 0: return true
    case 3: return false  // XMLLINT_ERR_VALID
    default: throw CheckError.xmllintFailed(file.lastPathComponent, status)
    }
  }

  private static func firstMessage(_ file: URL, schema: URL) async throws -> String? {
    let process = xmllint(file, schema: schema)
    let pipe = Pipe()
    process.standardError = pipe
    var data = Data()
    // Drained while it runs, or a document with more messages than the pipe buffers
    // never exits. This blocks a thread, but only for an unexplained failure.
    _ = try await exitStatus(of: process) { data = pipe.fileHandleForReading.readDataToEndOfFile() }
    // Without the path, which differs between runs and would move every report that has one.
    let first = String(decoding: data, as: UTF8.self).split(separator: "\n").first.map(String.init)
    return first.map { $0.replacingOccurrences(of: file.path, with: file.lastPathComponent) }
  }

  /// Runs `process` and suspends until it exits, without holding a thread meanwhile.
  /// `waitUntilExit` runs the current run loop until the child is gone -- in
  /// swift-corelibs-foundation, in 50 ms slices -- and it did so on a thread of the
  /// cooperative pool the conversions share, one fewer to parse on per xmllint running.
  private static func exitStatus(of process: Process, whileRunning body: () -> Void = {})
    async throws -> Int32
  {
    try await withCheckedThrowingContinuation { continuation in
      process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
      do {
        try process.run()
      } catch {
        process.terminationHandler = nil
        continuation.resume(throwing: error)
        return
      }
      body()
    }
  }

  private static func xmllint(_ file: URL, schema: URL) -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["xmllint", "--noout", "--relaxng", schema.path, file.path]
    process.standardOutput = FileHandle.nullDevice
    return process
  }

  enum CheckError: Error, CustomStringConvertible {
    case xmllintFailed(String, Int32)
    case schemaMissing(String)
    case xmllintMissing

    var description: String {
      switch self {
      case .xmllintFailed(let file, let status): "xmllint exited \(status) on \(file)"
      case .schemaMissing(let path):
        "no schema at \(path) (relative paths resolve from the working directory)"
      case .xmllintMissing: "xmllint is not on the path; on Linux it is libxml2-utils"
      }
    }
  }

  /// Every known cause present in `data`, in declaration order.
  static func causes(in data: Data) -> [Cause] {
    let finder = CauseFinder()
    let parser = XMLParser(data: data)
    parser.delegate = finder
    parser.parse()
    return Cause.allCases.filter(finder.found.contains)
  }
}

/// Walks a document once and notes every `SchemaCheck.Cause` it finds in it.
private final class CauseFinder: NSObject, XMLParserDelegate {
  var found: Set<SchemaCheck.Cause> = []

  private static let abstractBlocks: Set<String> = ["t", "dl", "ol", "ul"]
  /// The elements whose `target` is an `xsd:IDREF`. `<eref target>` is a URI.
  private static let targetElements: Set<String> = ["xref", "relref", "displayreference"]
  private static let mixedContent: Set<String> = ["li", "dd", "td", "th", "blockquote"]
  private static let inline: Set<String> = [
    "bcp14", "br", "cref", "em", "eref", "iref", "relref", "strong", "sub", "sup", "tt", "u",
    "xref",
  ]

  private struct Open {
    var name: String
    var hasAuthor = false
    var hasSection = false
    var hasInline = false
    var hasBlock = false
    var hasEntries = false
    var hasLists = false
  }

  private var stack: [Open] = []
  private var ids: Set<String> = []
  private var targets: Set<String> = []

  func parser(
    _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
    qualifiedName: String?, attributes: [String: String]
  ) {
    if let parent = stack.indices.last {
      if name == "author" { stack[parent].hasAuthor = true }
      if name == "section" { stack[parent].hasSection = true }
      if stack[parent].name == "abstract", !Self.abstractBlocks.contains(name) {
        found.insert(.blockInAbstract)
      }
      if name == "references",
        !["back", "references"].contains(stack[parent].name) || stack[parent].hasSection
      {
        found.insert(.misplacedReferences)
      }
      if stack[parent].name == "references" {
        if name == "references" { stack[parent].hasLists = true }
        if name == "reference" || name == "referencegroup" { stack[parent].hasEntries = true }
      }
      if Self.mixedContent.contains(stack[parent].name) {
        if Self.inline.contains(name) {
          stack[parent].hasInline = true
        } else {
          stack[parent].hasBlock = true
        }
      }
    }

    let anchor = attributes["anchor"]
    let partNumber = attributes["pn"]
    if let anchor, anchor == partNumber { found.insert(.anchorEqualsPartNumber) }
    // Every attribute `v3.rng` types `xsd:ID`. Counted once per element, so
    // `anchor == pn` is that cause and not also this one.
    let declared = [anchor, partNumber, attributes["slugifiedName"]].compactMap(\.self)
    for id in Set(declared) where !ids.insert(id).inserted {
      found.insert(.duplicateID)
    }
    // And every one it types `xsd:IDREF`.
    var referenced: [String] = []
    if Self.targetElements.contains(name), let target = attributes["target"] {
      referenced.append(target)
    }
    if name == "rfc", let extract = attributes["iprExtract"] { referenced.append(extract) }
    targets.formUnion(referenced)
    if (declared + referenced).contains(where: { !Self.isNCName($0) }) {
      found.insert(.idNotNCName)
    }

    stack.append(Open(name: name))
  }

  func parserDidEndDocument(_ parser: XMLParser) {
    if !targets.isSubset(of: ids) { found.insert(.danglingTarget) }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    guard let top = stack.indices.last, Self.mixedContent.contains(stack[top].name),
      string.contains(where: { !$0.isWhitespace })
    else { return }
    stack[top].hasInline = true
  }

  func parser(
    _ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?
  ) {
    guard let element = stack.popLast() else { return }
    if name == "front", !element.hasAuthor { found.insert(.frontWithoutAuthor) }
    if name == "middle", !element.hasSection { found.insert(.emptyMiddle) }
    if element.hasInline, element.hasBlock { found.insert(.inlineBesideBlocks) }
    if element.hasEntries, element.hasLists { found.insert(.misplacedReferences) }
  }

  /// XML's `NCName`, closely enough for what a converted RFC can contain: a letter or
  /// underscore, then letters, digits, `.`, `-` and `_`. No colon.
  static func isNCName(_ value: String) -> Bool {
    guard let first = value.first, first.isLetter || first == "_" else { return false }
    return value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }
  }
}
