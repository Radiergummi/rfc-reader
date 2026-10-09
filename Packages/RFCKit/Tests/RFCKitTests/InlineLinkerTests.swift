import Foundation
import Testing

@testable import RFCKit

/// `InlineLinker.link` on its own: a sentence in, inlines out. The sentences are
/// written in the shape of RFC prose, not quoted from any RFC, and each pins one
/// rule of the linker — which of two overlapping matches wins, where a URL ends,
/// how a list of numbers is linked, what a bracket that is not a citation becomes.
@Suite("Inline linker")
struct InlineLinkerTests {
  private let linker = InlineLinker(sectionNumbers: [], referenceTargets: [:])

  private func reference(_ number: Int, section: String? = nil) -> CrossReference.Target {
    .document(.rfc(number), section: section)
  }

  // MARK: - Overlaps

  /// "Section 4.2 of [RFC9110]" holds three matches — the section, the bracket and
  /// the RFC inside it — and the one that starts first and reaches furthest wins.
  @Test func `a section of an RFC is one reference, not three`() {
    let linker = InlineLinker(sectionNumbers: ["4.2"], referenceTargets: [:])
    #expect(
      linker.link("As in Section 4.2 of [RFC9110], a cache stores.") == [
        .text("As in "),
        .crossReference(CrossReference(target: reference(9110, section: "4.2"))),
        .text(", a cache stores."),
      ])
  }

  /// A section of a document the bibliography names by a tag is a section of that
  /// document, not of this one, though this one has a section of that number too
  /// (#768). The tag is the document's own name for the entry, so it is the label.
  @Test func `a section of a cited tag is a section of the document the tag names`() {
    let entry = CrossReference.Target.document(.rfc(9000), section: nil, entry: "ref-5")
    let linker = InlineLinker(sectionNumbers: ["3.2"], referenceTargets: ["5": entry])
    #expect(
      linker.link("as Section 3.2 of [5] describes") == [
        .text("as "),
        .crossReference(
          CrossReference(
            target: .document(.rfc(9000), section: "3.2", entry: "ref-5"),
            text: CrossReference.nonBreakingLabel("Section 3.2 of [5]"))),
        .text(" describes"),
      ])
  }

  /// A series tag the bibliography resolves to an RFC is the author's name for it: the
  /// label stays `[BCP14]`, not the RFC the entry opens.
  @Test func `a section of a series tag keeps the tag`() {
    let entry = CrossReference.Target.document(.rfc(2119), section: nil, entry: "BCP14")
    let linker = InlineLinker(sectionNumbers: [], referenceTargets: ["BCP14": entry])
    #expect(
      linker.link("Section 2 of [BCP14]") == [
        .crossReference(
          CrossReference(
            target: .document(.rfc(2119), section: "2", entry: "BCP14"),
            text: CrossReference.nonBreakingLabel("Section 2 of [BCP14]")))
      ])
  }

  /// An entry outside the series has no sections to open, but a section of it is
  /// still not one of this document's: it is the entry's (#473), worded as written.
  @Test func `a section of an entry outside the series is the entry's`() {
    let linker = InlineLinker(
      sectionNumbers: ["4"], referenceTargets: ["WIDGET": .anchor("ref-WIDGET")])
    #expect(
      linker.link("per Section 4 of [WIDGET].") == [
        .text("per "),
        .crossReference(
          CrossReference(
            target: .entrySection(entry: "ref-WIDGET", tag: "WIDGET", section: "4", url: nil))),
        .text("."),
      ])
  }

  /// A tag nothing resolves names some other document all the same: the section is
  /// left unlinked rather than linked into this one.
  @Test func `a section of an unknown tag is not this document's`() {
    let linker = InlineLinker(sectionNumbers: ["4"], referenceTargets: [:])
    #expect(linker.link("per Section 4 of [WIDGET].") == [.text("per Section 4 of [WIDGET].")])
  }

  /// Several sections of one RFC: each number is a section of it, read as the list
  /// wrote it, and the RFC is linked where it stands.
  @Test func `sections of an RFC each link into it`() {
    let linker = InlineLinker(sectionNumbers: ["3.2", "4"], referenceTargets: [:])
    #expect(
      linker.link("Sections 3.2 and 4 of RFC 793 apply") == [
        .text("Sections "),
        .crossReference(CrossReference(target: reference(793, section: "3.2"), text: "3.2")),
        .text(" and "),
        .crossReference(CrossReference(target: reference(793, section: "4"), text: "4")),
        .text(" of "),
        .crossReference(CrossReference(target: reference(793))),
        .text(" apply"),
      ])
  }

  /// The older spelling with a hyphen is a section of the RFC too, and keeps its
  /// hyphen.
  @Test func `a section of a hyphenated RFC links into it`() {
    let linker = InlineLinker(sectionNumbers: ["4"], referenceTargets: [:])
    #expect(
      linker.link("see Section 4 of RFC-793.") == [
        .text("see "),
        .crossReference(
          CrossReference(
            target: reference(793, section: "4"),
            text: CrossReference.nonBreakingLabel("Section 4 of RFC-793"))),
        .text("."),
      ])
  }

  /// A bracket starts a character before the RFC it holds, so the bracket wins.
  @Test func `a bracketed RFC is one reference to the document`() {
    #expect(
      linker.link("defined in [RFC2119].") == [
        .text("defined in "),
        .crossReference(CrossReference(target: reference(2119))),
        .text("."),
      ])
  }

  /// A bracket naming a reference the document lists goes where the list says,
  /// under the document's own tag.
  @Test func `a bracketed tag the references list resolves to its target`() throws {
    let target = reference(9000)
    let linker = InlineLinker(sectionNumbers: [], referenceTargets: ["TRANSPORT": target])
    let inlines = linker.link("see [TRANSPORT] for streams")
    #expect(inlines.count == 3)
    let found = try #require(inlines[1].crossReference, "the tag is not a reference: \(inlines)")
    #expect(found.target == target)
    #expect(found.text == CrossReference.nonBreakingLabel("[TRANSPORT]"))
  }

  // MARK: - Spellings

  /// The series' own spelling composes back identically, so it carries no label.
  @Test func `a plain RFC mention is linked with no label of its own`() {
    #expect(
      linker.link("RFC 1156 obsoletes it") == [
        .crossReference(CrossReference(target: reference(1156))),
        .text(" obsoletes it"),
      ])
  }

  /// The hyphen is the author's spelling, so it is kept as the label.
  @Test func `a hyphenated RFC mention is linked and keeps its hyphen`() {
    #expect(
      linker.link("RFC-1156 obsoletes it") == [
        .crossReference(
          CrossReference(target: reference(1156), text: CrossReference.nonBreakingLabel("RFC-1156"))
        ),
        .text(" obsoletes it"),
      ])
  }

  /// A name built on an RFC number -- a protocol item named after a format, a
  /// message field, a file name -- is a name, not a citation of the RFC, whether
  /// what follows the period is in capitals or in mixed case.
  @Test(arguments: [
    "a client may ask for RFC822.HEADER alone",
    "the slides are in RFC4321.PS on the server",
    "the domain taken from RFC5322.From is compared",
    "a verifier checks RFC5321.MailFrom first",
  ])
  func `a dotted name that starts with an RFC number stays text`(sentence: String) {
    #expect(linker.link(sentence) == [.text(sentence)])
  }

  /// Each number of a list is its own reference, linked where it stands; the word
  /// and the separators stay text.
  @Test func `every number of an RFC list is linked where it stands`() {
    #expect(
      linker.link("RFCs 734, 736 and 749 describe it.") == [
        .text("RFCs "),
        .crossReference(CrossReference(target: reference(734), text: "734")),
        .text(", "),
        .crossReference(CrossReference(target: reference(736), text: "736")),
        .text(" and "),
        .crossReference(CrossReference(target: reference(749), text: "749")),
        .text(" describe it."),
      ])
  }

  /// A page mark has the shape of a citation but names no document.
  @Test func `a bracket that is not a document stays text`() {
    #expect(linker.link("the end of the page [Page 3]") == [.text("the end of the page [Page 3]")])
  }

  // MARK: - Sections

  /// A section is linked only where the document has one by that number.
  @Test func `a section the document does not have stays text`() {
    let linker = InlineLinker(sectionNumbers: ["3"], referenceTargets: [:])
    #expect(
      linker.link("See Section 7 and Section 3.") == [
        .text("See Section 7 and "),
        .crossReference(
          CrossReference(
            target: .anchor("section-3"), text: CrossReference.nonBreakingLabel("Section 3"))),
        .text("."),
      ])
  }

  /// With no section numbers, as the XML parser runs it, no section is linked.
  @Test func `no section is linked without section numbers`() {
    #expect(linker.link("See Section 3.") == [.text("See Section 3.")])
  }

  // MARK: - URLs

  /// The punctuation that closes a sentence or a parenthesis is not the URL's, and
  /// stays as text after it.
  @Test(arguments: [")", ".", ",", ";", "\"", ")."])
  func `a URL ends before trailing punctuation`(punctuation: String) throws {
    let url = try #require(URL(string: "https://example.com/draft.txt"))
    #expect(
      linker.link("(at https://example.com/draft.txt\(punctuation) today") == [
        .text("(at "),
        .link(url, [.text("https://example.com/draft.txt")]),
        .text("\(punctuation) today"),
      ])
  }

  /// The end of the link is counted in the text it came from, so what follows it is
  /// all there, whatever the URL holds.
  @Test func `the text after a URL is kept whole`() throws {
    let url = try #require(URL(string: "https://example.com/a?b=c&d=e"))
    #expect(
      linker.link("https://example.com/a?b=c&d=e. Then more.") == [
        .link(url, [.text("https://example.com/a?b=c&d=e")]),
        .text(". Then more."),
      ])
  }

  /// A URL into the RFC series cites the document it names, as an `<eref>` to it reads,
  /// whichever site it points at, and keeps the words the prose spelled it in (#683).
  @Test(arguments: [
    "http://www.rfc-editor.org/info/rfc4321", "https://datatracker.ietf.org/doc/html/rfc4321",
  ])
  func `a URL into the RFC series cites its document`(address: String) {
    #expect(
      linker.link("Defined at \(address) for now.") == [
        .text("Defined at "),
        .crossReference(CrossReference(target: reference(4321), text: address)),
        .text(" for now."),
      ])
  }

  /// A URL a citation cannot say all of, its errata or an anchor, stays a link.
  @Test func `a URL to a page about an RFC stays a link`() throws {
    let address = "https://www.rfc-editor.org/errata/rfc4321"
    let url = try #require(URL(string: address))
    #expect(
      linker.link("See \(address).") == [.text("See "), .link(url, [.text(address)]), .text(".")])
  }

  // MARK: - Nothing to link

  @Test func `prose with nothing to link is one run of text`() {
    #expect(linker.link("An ordinary sentence.") == [.text("An ordinary sentence.")])
  }

  @Test func `an empty string links to nothing`() {
    #expect(linker.link("").isEmpty)
  }
}
