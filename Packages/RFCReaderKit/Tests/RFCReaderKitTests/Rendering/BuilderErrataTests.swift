import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// A heading whose section has a verified or held erratum has a chip after it, which
/// lists them (#387). Those naming no section the document has are the whole
/// document's, and go by the title, which is not in the text.
@Suite("Builder: errata")
struct BuilderErrataTests {
  private static func erratum(
    _ id: Int, _ status: Erratum.Status, section: String
  ) -> Erratum {
    Erratum(
      id: id, document: .rfc(9999), status: status, type: .technical, section: section,
      original: "old", corrected: "new", notes: "", submitted: "2024-01-01")
  }

  private static let document = RFCDocument(
    header: DocumentHeader(title: "T"),
    sections: [
      Section(
        anchor: "one", number: "1", title: "One", blocks: [.paragraph(Paragraph(text: "x"))]),
      Section(
        anchor: "two", number: "2", title: "Two", blocks: [.paragraph(Paragraph(text: "y"))]),
    ],
    source: .xml)

  private static func marks(_ errata: [Erratum]) -> ErrataMarks {
    ErrataMarks(errata: errata, document: document, locale: .english)
  }

  // MARK: - Where they go

  @Test func `an erratum goes on each section it names, and the rest on the document`() {
    let marks = Self.marks([
      Self.erratum(1, .verified, section: "1"),
      Self.erratum(2, .verified, section: "In Sections 1 and 2"),
      Self.erratum(3, .verified, section: "GLOBAL"),
      // A section the document doesn't have is never guessed onto another.
      Self.erratum(4, .verified, section: "7"),
      Self.erratum(5, .reported, section: "2"),
    ])

    #expect(marks.bySection["one"]?.map(\.id) == [1, 2])
    #expect(marks.bySection["two"]?.map(\.id) == [2])
    #expect(marks.document.map(\.id) == [3, 4])
  }

  @Test(arguments: [
    ([Erratum.Status.verified], "Erratum"),
    ([.verified, .verified], "2 errata"),
    ([.heldForDocumentUpdate], "Held erratum"),
    ([.heldForDocumentUpdate, .heldForDocumentUpdate], "2 held errata"),
    ([.verified, .verified, .heldForDocumentUpdate], "2 errata, 1 held"),
    ([.verified, .heldForDocumentUpdate, .heldForDocumentUpdate], "1 erratum, 2 held"),
  ])
  func `a chip says how many, and which are held`(statuses: [Erratum.Status], label: String) {
    let errata = statuses.enumerated().map { Self.erratum($0.offset, $0.element, section: "1") }
    let items = Self.marks(errata).bySection["one"] ?? []
    #expect(ErrataMarks.bodyLabel(for: items) == label)
    #expect(ErrataMarks.label(for: items, locale: .english) == label)
  }

  /// The reader leaves a bibliography to the inspector, heading and all, so an
  /// erratum naming one goes by the title, as the Info pane lists it.
  @Test func `an erratum naming a bibliography is the whole document's`() {
    let document = RFCDocument(
      header: DocumentHeader(title: "T"),
      sections: [
        Section(
          anchor: "one", number: "1", title: "One", blocks: [.paragraph(Paragraph(text: "x"))]),
        Section(
          anchor: "refs", number: "2", title: "References",
          subsections: [
            Section(
              anchor: "normative", number: "2.1", title: "Normative References",
              blocks: [.references(ReferenceList(title: "Normative References", entries: []))])
          ]),
      ],
      source: .xml)
    #expect(document.sections[1].subsections[0].holdsOnlyReferences)

    let marks = ErrataMarks(
      errata: [
        Self.erratum(1, .verified, section: "2.1"), Self.erratum(2, .verified, section: "1"),
      ],
      document: document, locale: .english)

    #expect(marks.bySection.keys.sorted() == ["one"])
    #expect(marks.document.map(\.id) == [1])
  }

  /// The Info pane is given the sections the contents panel lists, a flat list whose
  /// entries keep their subsections, drawn or not. Through `drawn` it finds the same
  /// sections the chips do, and offers no link to a bibliography the reader left out.
  @Test func `the Info pane's errata go to the sections the chips are on`() {
    let document = RFCDocument(
      header: DocumentHeader(title: "T"),
      sections: [
        Section(
          anchor: "refs", number: "1", title: "References",
          blocks: [.paragraph(Paragraph(text: "x"))],
          subsections: [
            Section(
              anchor: "normative", number: "1.1", title: "Normative References",
              blocks: [.references(ReferenceList(title: "Normative References", entries: []))])
          ])
      ],
      source: .xml)
    let flat = document.allSections
    #expect(flat.map(\.anchor) == ["refs", "normative"])

    let summary = ErrataSummary(
      errata: [Self.erratum(1, .verified, section: "1.1")], sections: ErrataMarks.drawn(flat),
      locale: .english)

    #expect(summary.items.map(\.anchor) == [nil])
  }

  /// An original shown without a body has no sections to put an erratum on.
  @Test func `without a document every erratum is the whole document's`() {
    let marks = ErrataMarks(
      errata: [Self.erratum(1, .verified, section: "1")], document: nil, locale: .english)
    #expect(marks.bySection.isEmpty)
    #expect(marks.document.map(\.id) == [1])
  }

  // MARK: - The chip

  private func chips(in text: NSAttributedString) -> [(range: NSRange, anchor: String)] {
    var found: [(range: NSRange, anchor: String)] = []
    text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) {
      value, range, _ in
      if let url = value as? URL, let anchor = ReaderLinkScheme.errata(from: url) {
        found.append((range, anchor))
      }
    }
    return found
  }

  @Test func `a heading with errata has a chip after its title`() throws {
    let built = DocumentTextBuilder.build(
      Self.document, style: ReadingStyle(),
      errata: Self.marks([
        Self.erratum(1, .verified, section: "2"), Self.erratum(2, .verified, section: "2"),
      ]))

    let chip = try #require(chips(in: built.text).first)
    #expect(chips(in: built.text).map(\.anchor) == ["two"])
    let string = built.text.string as NSString
    let heading = try Fixtures.offset(of: "2. Two", in: built.text)
    #expect(chip.range.location > heading)
    // The symbol, the joiner, then the words, before the heading's line break.
    #expect(string.substring(with: chip.range).hasSuffix("2\u{00A0}errata"))
    #expect(string.substring(from: NSMaxRange(chip.range)).hasPrefix("\n"))
    // A chip, drawn as a reference's is, which nothing copies.
    for offset in chip.range.location..<NSMaxRange(chip.range) {
      #expect(built.text.attribute(.rfcChip, at: offset, effectiveRange: nil) != nil)
      #expect(built.text.attribute(.rfcReaderOnly, at: offset, effectiveRange: nil) != nil)
    }
    #expect(built.errata(of: "two").map(\.id) == [1, 2])
  }

  /// Copying a heading copies its words, not the chip or the space before it.
  @Test func `the space before the chip is not copied either`() throws {
    let built = DocumentTextBuilder.build(
      Self.document, style: ReadingStyle(),
      errata: Self.marks([Self.erratum(1, .verified, section: "1")]))

    let chip = try #require(chips(in: built.text).first)
    let space = chip.range.location - 1
    #expect((built.text.string as NSString).character(at: space) == 0x20)
    #expect(built.text.attribute(.rfcReaderOnly, at: space, effectiveRange: nil) != nil)
  }

  @Test func `a heading without errata has no chip`() {
    let built = DocumentTextBuilder.build(
      Self.document, style: ReadingStyle(),
      errata: Self.marks([Self.erratum(1, .verified, section: "GLOBAL")]))

    #expect(chips(in: built.text).isEmpty)
    #expect(built.errata(of: "one").isEmpty)
  }

  /// Like a reference's label, the chip never wraps between its words: a line too
  /// short for it takes it whole onto the next.
  @Test func `a chip's words do not break`() throws {
    let built = DocumentTextBuilder.build(
      Self.document, style: ReadingStyle(),
      errata: Self.marks([
        Self.erratum(1, .verified, section: "1"),
        Self.erratum(2, .heldForDocumentUpdate, section: "1"),
      ]))

    let chip = try #require(chips(in: built.text).first)
    let words = (built.text.string as NSString).substring(with: chip.range)
    #expect(words.hasSuffix("1\u{00A0}erratum,\u{00A0}1\u{00A0}held"))
    #expect(!words.contains(" "))
  }

  /// Chrome beside the heading rather than part of it: set as the backlink caption
  /// under the heading is, not in the heading's own size and weight.
  @Test func `a chip is set in the caption's font`() throws {
    let style = ReadingStyle()
    let built = DocumentTextBuilder.build(
      Self.document, style: style,
      errata: Self.marks([Self.erratum(1, .verified, section: "1")]))

    let chip = try #require(chips(in: built.text).first)
    let font = try #require(
      built.text.attribute(.font, at: NSMaxRange(chip.range) - 1, effectiveRange: nil)
        as? PlatformFont)
    #expect(font == style.backlinksFont)
  }

  @Test func `a chip is said as its words`() throws {
    let built = DocumentTextBuilder.build(
      Self.document, style: ReadingStyle(),
      errata: Self.marks([Self.erratum(1, .heldForDocumentUpdate, section: "1")]))

    let chip = try #require(chips(in: built.text).first)
    let spoken = built.text.attribute(
      .rfcSpoken, at: NSMaxRange(chip.range) - 1, effectiveRange: nil)
    #expect(spoken as? String == "Held erratum")
  }

  @Test func `the errata chip at an offset is found by its anchor`() throws {
    let built = DocumentTextBuilder.build(
      Self.document, style: ReadingStyle(),
      errata: Self.marks([Self.erratum(1, .verified, section: "1")]))

    let chip = try #require(chips(in: built.text).first)
    let found = try #require(built.text.errataChip(at: chip.range.location + 1))
    #expect(found.anchor == "one")
    #expect(found.range == chip.range)
    #expect(built.text.errataChip(at: 0) == nil)
  }

  /// A right-click below the last line asks at the end of the text.
  @Test func `there is no errata chip past the end`() {
    let built = DocumentTextBuilder.build(
      Self.document, style: ReadingStyle(),
      errata: Self.marks([Self.erratum(1, .verified, section: "1")]))

    #expect(built.text.errataChip(at: built.text.length) == nil)
    #expect(built.text.errataChip(at: -1) == nil)
  }
}
