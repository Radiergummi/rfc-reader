import Foundation
import Testing

@testable import RFCKit

/// Cross references and links, as the legacy parser runs the linker over prose.
@Suite("Legacy text parser: inline links")
struct LegacyTextParserLinkingTests {
  /// `[RFC 2211]` matched neither pattern: the bracket pattern's anchor admitted no
  /// space or comma, and the bare pattern discarded anything a `[` preceded.
  /// Between them they dropped 1,606 of the 1,640 unlinked RFC mentions left in the
  /// corpus's prose. RFC 2606 sets its citations `[RFC 1034]`; RFC 2147 writes a
  /// multi-anchor `[RFC1883, Section 4.3]`, where the bracket is not ours to eat.
  @Test func `bracketed RFC mentions link whatever their spacing`() throws {
    let spaced = try Fixtures.document("rfc2606.txt")
    #expect(spaced.referencedDocuments.contains(.rfc(1034)), "[RFC 1034] names a document")

    let multi = try Fixtures.document("rfc2147.txt")
    #expect(multi.referencedDocuments.contains(.rfc(1883)))
    let notes = multi.paragraphs.filter { $0.plainText.hasPrefix("Note 2") }
    let note = try #require(notes.first)
    // The tags beside the RFC are the author's, so the brackets stay as text and
    // only the reference inside them is linked.
    #expect(note.plainText.contains(", Section 4.3]"))
  }

  /// A definition's term cites a document as its text does, and the XML parser links
  /// both when it reads the conversion back, so a term the converter left as text
  /// changed on a second serialization (#683).
  @Test func `a definition's term is linked like its text`() throws {
    let linker = InlineLinker(sectionNumbers: [], referenceTargets: [:])
    let items = LegacyTextParser.definitionItems(
      [(term: "RFC 4321:", text: "An example protocol.")],
      in: .init(proseIndent: LegacyTextParser.classicProseIndent, linker: linker))
    let item = try #require(items.first)
    #expect(
      item.term.compactMap(\.crossReference).map(\.target) == [
        .document(.rfc(4321), section: nil, entry: nil)
      ])
    #expect(item.term.plainText == "RFC\u{00A0}4321:", "the label prose gives it")
  }

  @Test func `legacy bracketed RFC labels are flagged as canonical`() throws {
    let document = try Fixtures.document("rfc5234.txt")
    let xrefs = document.crossReferences
    // Measured over 1,200 corpus documents before this rule was fixed: 12,612
    // references, 253 of them chips. The rest were exactly this case.
    let canonical = try #require(
      xrefs.first { xref in
        guard case .document(let id, _, _) = xref.target, id.series == .rfc else { return false }
        return xref.isCanonicalLabel
      }, "without this, 98% of the library shows no chips")
    #expect(canonical.text == nil)
    #expect(canonical.label.hasPrefix("[RFC"))
    let authored = try #require(xrefs.first { $0.text == "[US-ASCII]" })
    #expect(!authored.isCanonicalLabel, "an author's own tag must survive verbatim")
  }

  /// `link` skips a pattern whose opening literal the fragment lacks. That is only
  /// sound while every match of the pattern holds the literal, so wherever a pattern
  /// matches -- over every line of every fixture, and the shapes a
  /// byte test and a grapheme test could disagree on -- its literal must be set.
  @Test func `the literal gate skips no match`() throws {
    let directory = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    var fragments = [
      "RFC\u{0301} 1", "\u{FEFF}RFC 1", "ＲＦＣ 1", "rfc 1", "section 2", "HTTP://x", "RFC\r\n1",
      "RFC\u{00A0}1", "Section\u{00A0}2 of RFC 1", "R", "RF", "Sectio", "[", "[RFC1]",
      "RFCs 1, 2 and 3", "Section 2 of [A]", "Sections 1 and 2 of RFC-3", "",
    ]
    for fixture in try FileManager.default.contentsOfDirectory(atPath: directory.path)
    where fixture.hasSuffix(".txt") {
      fragments += try Fixtures.string(fixture).components(separatedBy: "\n")
    }
    for fragment in fragments {
      let literals = InlineLinker.Literals(in: fragment)
      let label = fragment.prefix(80).debugDescription
      // Each pattern is asked about its own gate: the pairing is the pattern's, not the test's.
      func check<Output>(_ pattern: InlineLinker.Gated<Output>) {
        if fragment.contains(pattern.regex) { #expect(literals[keyPath: pattern.gate], "\(label)") }
      }
      check(InlineLinker.sectionOfDocumentPattern)
      check(InlineLinker.bracketPattern)
      check(InlineLinker.bareRFCPattern)
      check(InlineLinker.rfcListPattern)
      check(InlineLinker.sectionPattern)
      check(InlineLinker.urlPattern)
    }
  }

  /// Two more spellings the linker was blind to, both common in the older half of
  /// the series: `RFC-791`, and a list written once as `RFCs 765, 821 and 854`.
  /// Measured on the corpus, prose held 2,223 of the first and 659 of the second,
  /// against 1,640 of the plain `RFC 791` the linker already knew.
  @Test func `hyphenated and plural mentions link`() throws {
    let document = try Fixtures.document("rfc980.txt")
    let xrefs = document.crossReferences
    let byTarget = Dictionary(
      xrefs.map { ($0.target, $0) }, uniquingKeysWith: { first, _ in first })

    // The hyphen is the author's, not ours: `isCanonicalTag` does not count it as
    // the series' own spelling, so the words stay exactly as they were set.
    let hyphenated = try #require(byTarget[.document(.rfc(791), section: nil)])
    #expect(hyphenated.text == "RFC-791")
    #expect(byTarget[.document(.rfc(793), section: nil)]?.text == "RFC-793")

    // A number in a list reads as the list wrote it -- composing "RFC 821" over
    // the top of "RFCs 765, 821" would say RFC twice.
    let inList = try #require(byTarget[.document(.rfc(821), section: nil)])
    #expect(inList.text == "821")
    #expect(Set(document.referencedDocuments).isSuperset(of: [.rfc(765), .rfc(821), .rfc(854)]))
  }
}
