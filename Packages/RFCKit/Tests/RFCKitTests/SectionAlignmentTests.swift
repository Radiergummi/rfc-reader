import Foundation
import Testing

@testable import RFCKit

/// Which section of a successor replaces each section of the document it obsoletes
/// (#388). The guards build their two documents in code, from a few hand-written
/// titles and lines each; the measurement aligns RFC 9110 with the documents it
/// obsoletes.
@Suite("Section alignment")
struct SectionAlignmentTests {
  private static func document(_ number: Int, _ sections: [Section]) -> RFCDocument {
    var header = DocumentHeader(title: "RFC \(number)")
    header.id = .rfc(number)
    return RFCDocument(header: header, sections: sections, source: .xml)
  }

  private static func section(_ number: String, _ title: String, _ text: String) -> Section {
    Section(
      anchor: "section-\(number)", number: number, title: title,
      blocks: [.paragraph(Paragraph(text: text))])
  }

  /// `old` and `new` aligned, with the edge between them in `new`'s header, where the
  /// index finds it.
  private static func pairs(old: RFCDocument, new: RFCDocument) -> [AlignedSection] {
    var new = new
    if let id = old.header.id { new.header.obsoletes.append(id) }
    return SectionAlignment.pairs(among: [old, new])
  }

  private static func numbers(_ pairs: [AlignedSection]) -> Set<String> {
    Set(pairs.map { "\($0.oldSection) -> \($0.newSection)" })
  }

  /// A renumbered section keeps its title: the old one's place is no clue to the new
  /// one's, and the order of the two documents is no clue either.
  @Test func `a renumbered section is aligned by its title`() {
    let old = Self.document(
      1,
      [
        Self.section("1", "Widget Requests", "A client asks for a widget by sending its name."),
        Self.section("2", "Gadget Responses", "A server answers with the gadget it holds."),
      ])
    let new = Self.document(
      2,
      [
        Self.section("1", "Overview", "This document describes gizmos and their uses."),
        Self.section("4", "Gadget Responses", "A server answers with the gadget it holds now."),
        Self.section("7", "Widget Requests", "A client asks for a widget by name."),
      ])
    let pairs = Self.pairs(old: old, new: new)
    #expect(Self.numbers(pairs) == ["section-1 -> section-7", "section-2 -> section-4"])
    #expect(pairs.allSatisfy { $0.old == .rfc(1) && $0.new == .rfc(2) })
  }

  /// A retitled section is found by what it says, which has to be more than its
  /// title does.
  @Test func `a retitled section is aligned by its content`() {
    let framing =
      "A message carries a representation, framed by the transfer coding and"
      + " delimited by its length. A recipient that cannot determine the length closes"
      + " the connection. Framing is independent of the media type."
    let old = Self.document(
      1,
      [
        Self.section("3", "Payload Semantics", framing),
        Self.section("4", "Request Methods", "A method names what the client wants done."),
      ])
    let new = Self.document(
      2,
      [
        Self.section("2", "Methods", "A method names what the client wants done to a resource."),
        Self.section("6", "Content", framing),
      ])
    let pairs = Self.pairs(old: old, new: new)
    #expect(Self.numbers(pairs).contains("section-3 -> section-6"))
    #expect(!Self.numbers(pairs).contains("section-3 -> section-2"))
  }

  /// A section split in two has both halves for its successors, so a reader of
  /// either half finds where it came from.
  @Test func `a split section is aligned with each part`() {
    let old = Self.document(
      1,
      [
        Self.section(
          "5", "Validators",
          "A modification date validator compares timestamps. An entity tag validator compares opaque tags."
        )
      ])
    let new = Self.document(
      2,
      [
        Self.section(
          "8.1", "Modification Date Validators",
          "A modification date validator compares timestamps."),
        Self.section(
          "8.2", "Entity Tag Validators", "An entity tag validator compares opaque tags."),
      ])
    let pairs = Self.pairs(old: old, new: new)
    #expect(Self.numbers(pairs) == ["section-5 -> section-8.1", "section-5 -> section-8.2"])
  }

  /// A document obsoleted by two is aligned with both at once: a section that moved
  /// to one is paired there, and not also with its nearest match in the other.
  @Test func `a section that moved to another successor is paired only there`() {
    let old = Self.document(
      1,
      [
        Self.section("1", "Widget Requests", "A client asks for a widget by sending its name."),
        Self.section(
          "2", "Widget Framing", "Each widget request is framed by a length and a checksum."),
      ])
    var semantics = Self.document(
      2, [Self.section("3", "Widget Requests", "A client asks for a widget by sending its name.")])
    var syntax = Self.document(
      3,
      [
        Self.section(
          "4", "Widget Framing", "Each widget request is framed by a length and a checksum.")
      ])
    semantics.header.obsoletes = [.rfc(1)]
    syntax.header.obsoletes = [.rfc(1)]
    let pairs = SectionAlignment.pairs(among: [old, semantics, syntax])
    #expect(
      Set(pairs.map { "\($0.oldSection) -> \($0.new.number) \($0.newSection)" })
        == ["section-1 -> 2 section-3", "section-2 -> 3 section-4"])
  }

  /// The same the other way: a document obsoleting two takes each section's
  /// predecessor from the one that holds it, not the nearest match from each.
  @Test func `a section whose predecessor is in another old document is paired only there`() {
    let requests = Self.document(
      1, [Self.section("1", "Widget Requests", "A client asks for a widget by sending its name.")])
    let framing = Self.document(
      2,
      [
        Self.section(
          "1", "Widget Framing", "Each widget request is framed by a length and a checksum.")
      ])
    var merged = Self.document(
      3,
      [
        Self.section("5", "Widget Requests", "A client asks for a widget by sending its name."),
        Self.section(
          "6", "Widget Framing", "Each widget request is framed by a length and a checksum."),
      ])
    merged.header.obsoletes = [.rfc(1), .rfc(2)]
    let pairs = SectionAlignment.pairs(among: [requests, framing, merged])
    #expect(
      Set(pairs.map { "\($0.old.number) \($0.oldSection) -> \($0.newSection)" })
        == ["1 section-1 -> section-5", "2 section-1 -> section-6"])
  }

  /// A title alone is not enough: two sections that share a generic title and nothing
  /// they say are no pair.
  @Test func `an equal title with nothing in common is no pair`() {
    let old = Self.document(
      1, [Self.section("1", "Overview", "Widgets are requested by name and returned whole.")])
    let new = Self.document(
      2, [Self.section("9", "Overview", "Telemetry counters export daily over a side channel.")])
    #expect(Self.pairs(old: old, new: new).isEmpty)
  }

  /// An edge named twice is one edge, and a document naming itself is none.
  @Test func `a repeated or a self-naming edge writes nothing more`() {
    let old = Self.document(
      1, [Self.section("1", "Widget Requests", "A client asks for a widget by sending its name.")])
    var new = Self.document(
      2, [Self.section("1", "Widget Requests", "A client asks for a widget by sending its name.")])
    new.header.obsoletes = [.rfc(1), .rfc(1), .rfc(2)]
    let pairs = SectionAlignment.pairs(among: [old, new, new])
    #expect(pairs.count == 1)
    #expect(pairs.allSatisfy { $0.old == .rfc(1) && $0.new == .rfc(2) })
  }

  /// A section with nothing in common with any old one has no predecessor: a new
  /// section is not given the nearest old one.
  @Test func `a section with nothing in common has no predecessor`() {
    let old = Self.document(
      1, [Self.section("1", "Widget Requests", "A client asks for a widget by sending its name.")])
    let new = Self.document(
      2,
      [
        Self.section("1", "Widget Requests", "A client asks for a widget by sending its name."),
        Self.section(
          "2", "Telemetry Export", "Counters are exported over a separate channel daily."),
      ])
    let pairs = Self.pairs(old: old, new: new)
    #expect(!pairs.contains { $0.newSection == "section-2" })
  }

  /// A row has to say which two documents it relates.
  @Test func `a document without a number aligns nothing`() {
    var old = Self.document(
      1, [Self.section("1", "Widget Requests", "A client asks for a widget by sending its name.")])
    old.header.id = nil
    let new = Self.document(
      2, [Self.section("1", "Widget Requests", "A client asks for a widget by sending its name.")])
    #expect(Self.pairs(old: old, new: new).isEmpty)
  }
}

/// The alignment of RFC 9110 with the documents it obsoletes, measured against
/// labels written by hand. Its Appendix B lists, for each of them, the sections of
/// 9110 that changed, and names only 9110's: the predecessor of each was looked up
/// by hand in the old document, and only section numbers are written here (#388).
/// A section the appendix names under a document that has no counterpart for it is
/// labeled as having none, and so is any pair claimed for it a wrong one. A section
/// that merges two old ones has both, such as 9110 §2.2, which is RFC 7230's
/// "Requirements Notation" and its conformance section. The few whose counterpart is
/// unclear are left out, rather than labeled either way: 4.1, 4.3.1 and 5.5, and
/// 5.6.6 under RFC 7231.
///
/// The floors are what `SectionAlignment.threshold` was set to reach, measured
/// rather than hoped for, so a change that loses either fails here.
@Suite(
  "Corpus-backed: section alignment",
  .enabled(if: CorpusText.isAvailable && CorpusText.isXMLAvailable))
struct CorpusBackedSectionAlignmentTests {
  /// For each old document, its sections and the 9110 sections that replace them.
  private static let predecessors: [Int: [(old: String, new: String)]] = [
    7230: [
      ("1.1", "2.2"), ("2.5", "2.2"), ("2.7.1", "4.2.1"), ("2.7.2", "4.2.2"), ("3.2.6", "5.6.6"),
      ("3.2", "6.3"), ("4.1.2", "6.5.1"), ("5.1", "7.1"), ("5.5", "7.1"), ("5.4", "7.2"),
      ("5.2", "7.3.3"), ("5.7.1", "7.6.3"),
    ],
    7231: [
      ("3.3", "6.4"), ("4.2.2", "9.2.2"), ("4.3.1", "9.3.1"), ("4.3.2", "9.3.2"),
      ("4.3.4", "9.3.4"), ("4.3.5", "9.3.5"), ("4.3.7", "9.3.7"), ("4.3.8", "9.3.8"),
      ("5.1.1", "10.1.1"), ("5.3", "12.3"), ("5.3.2", "12.5.1"), ("5.3.3", "12.5.2"),
      ("7.1.4", "12.5.5"), ("6.4", "15.4"),
    ],
    7232: [("2.2.2", "8.8.2.2"), ("3.1", "13.1.1"), ("3.4", "13.1.4"), ("5", "13.2")],
    7233: [("2", "14.1"), ("2.2", "14.1"), ("3.1", "14.2"), ("2.3", "14.3")],
    7538: [("3", "15.4.9")],
  ]

  /// For each old document, the 9110 sections the appendix names under it that have no
  /// counterpart in it.
  private static let newcomers: [Int: [String]] = [
    7230: ["7.4"],
    7231: ["6", "15.4.9", "15.5.20", "15.5.21"],
    7233: ["14.5"],
  ]

  /// The sections of RFC 7230 that went to RFC 9112, the other document obsoleting it,
  /// and have no counterpart in 9110: the message syntax and framing, and pipelining.
  private static let movedTo9112 = [
    "3.1.1", "3.1.2", "3.3.1", "3.3.3", "4.1", "4.1.1", "4.1.3", "5.3.1", "5.3.4", "6.3.2",
    "9.5",
  ]

  /// An old document as `corpus-build index` reads it: converted to RFCXML and parsed
  /// back, under the number its file names.
  private static func old(_ number: Int) throws -> RFCDocument {
    let parsed = LegacyTextParser.parse(try CorpusText.text("rfc\(number)"))
    var document = try RFCXMLParser.parse(Data(RFCXMLSerializer().serialize(parsed).utf8))
    document.header.id = .rfc(number)
    return document
  }

  private static func new(_ number: Int) throws -> RFCDocument {
    var document = try RFCXMLParser.parse(CorpusText.xml("rfc\(number)"))
    document.header.id = .rfc(number)
    return document
  }

  /// Each section's number, by anchor.
  private static func numbers(of document: RFCDocument) -> [String: String] {
    Dictionary(
      document.allSections.compactMap { section in section.number.map { (section.anchor, $0) } },
      uniquingKeysWith: { first, _ in first })
  }

  /// The documents RFC 9110 obsoletes, as `corpus-build index` aligns them: together,
  /// with 9110 and with 9112, the other document obsoleting 7230.
  private static let olds = [2818, 7230, 7231, 7232, 7233, 7235, 7538, 7615, 7694]

  /// The group's pairs with 9110 for each old document, by section number.
  private static func pairsWith9110() throws -> [Int: [(old: String, new: String)]] {
    let olds = try Self.olds.map(Self.old)
    let new = try Self.new(9110)
    let numbers = Dictionary(
      uniqueKeysWithValues: (olds + [new]).compactMap { document in
        document.header.id.map { ($0, Self.numbers(of: document)) }
      })
    let pairs = SectionAlignment.pairs(among: olds + [new, try Self.new(9112)])
    var byOld: [Int: [(old: String, new: String)]] = [:]
    for pair in pairs where pair.new == .rfc(9110) {
      guard let oldNumber = numbers[pair.old]?[pair.oldSection],
        let newNumber = numbers[pair.new]?[pair.newSection]
      else { continue }
      byOld[pair.old.number, default: []].append((oldNumber, newNumber))
    }
    return byOld
  }

  /// A section that moved to the other successor gets no row in this one: its best
  /// match in 9110 would be a wrong "replaced by".
  @Test func `a section that went to another successor is not aligned with this one`() throws {
    let pairs = try Self.pairsWith9110()[7230] ?? []
    let wrong = pairs.filter { Self.movedTo9112.contains($0.old) }
    #expect(wrong.isEmpty, "\(wrong.map { "7230 §\($0.old) -> 9110 §\($0.new)" })")
  }

  @Test func `RFC 9110 is aligned with what it obsoletes`() throws {
    let aligned = try Self.pairsWith9110()
    var claimed = 0
    var right = 0
    var found = 0
    var wrong: [String] = []
    var missed: [String] = []
    for (number, labeled) in Self.predecessors {
      let labeledSections = Set(labeled.map(\.new)).union(Self.newcomers[number] ?? [])
      let pairs = aligned[number] ?? []
      for pair in pairs where labeledSections.contains(pair.new) {
        claimed += 1
        if labeled.contains(where: { $0.old == pair.old && $0.new == pair.new }) {
          right += 1
        } else {
          wrong.append("\(number) §\(pair.old) -> 9110 §\(pair.new)")
        }
      }
      for label in labeled {
        if pairs.contains(where: { $0.old == label.old && $0.new == label.new }) {
          found += 1
        } else {
          missed.append("\(number) §\(label.old) -> 9110 §\(label.new)")
        }
      }
    }
    let labels = Self.predecessors.values.map(\.count).reduce(0, +)
    let precision = Double(right) / Double(max(claimed, 1))
    let recall = Double(found) / Double(labels)
    let report =
      "precision \(right)/\(claimed), recall \(found)/\(labels); "
      + "wrong: \(wrong.sorted()); missed: \(missed.sorted())"
    print(report)
    #expect(precision >= 0.9, "\(report)")
    #expect(recall >= 0.85, "\(report)")
  }
}
