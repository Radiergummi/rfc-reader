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
