import Foundation
import Testing

@testable import RFCKit

/// What the Services turn a selection into (#195): hand-written citations in the
/// shapes the issue lists and the shapes prose sets them in, never quoted from an RFC.
@Suite("Citation links")
struct CitationLinkTests {
  @Test(
    arguments: [
      ("RFC 9110 §8.3", "rfc://9110#section-8.3"),
      ("RFC 9110 § 8.3", "rfc://9110#section-8.3"),
      ("§8.3 of RFC 9110", "rfc://9110#section-8.3"),
      ("RFC 9110, Section 8.3", "rfc://9110#section-8.3"),
      ("Section 8.3 of RFC 9110", "rfc://9110#section-8.3"),
      ("Section 8.3 of [RFC9110]", "rfc://9110#section-8.3"),
      ("[RFC9110], Section 8.3", "rfc://9110#section-8.3"),
      ("[RFC9110]", "rfc://9110"),
      ("RFC 9110", "rfc://9110"),
      ("RFC-1156", "rfc://1156"),
      ("[BCP14]", "rfc://bcp14"),
      ("BCP 14", "rfc://bcp14"),
      ("RFC 9110, Appendix B", "rfc://9110#appendix-B"),
      ("Appendix A.1 of RFC 9110", "rfc://9110#appendix-A.1"),
      ("RFC 1122 Appendix 1", "rfc://1122#appendix-1"),
      ("https://www.rfc-editor.org/rfc/rfc9110.html#section-8.3", "rfc://9110#section-8.3"),
    ])
  func `a citation becomes the link to its place`(selection: String, expected: String) {
    #expect(CitationLink.link(in: selection)?.appURL.absoluteString == expected)
  }

  /// A selection is whatever the cursor caught: the words of a comment around the
  /// citation, a line break inside it.
  @Test(
    arguments: [
      "// see RFC 9110 §8.3.",
      "as defined in RFC 9110,\n   Section 8.3",
      "  Section 8.3 of [RFC9110]  ",
      "(RFC 9110, Section 8.3)",
    ])
  func `the words around a citation are not part of it`(selection: String) {
    #expect(CitationLink.link(in: selection)?.appURL.absoluteString == "rfc://9110#section-8.3")
  }

  /// The same document twice is one citation; anything that leaves the place in
  /// doubt is none.
  @Test(
    arguments: [
      ("RFC 9110 (see [RFC9110])", "rfc://9110"),
      ("Section 8.3 of RFC 9110 ([RFC9110])", "rfc://9110#section-8.3"),
      ("[RFC9110] (RFC 9110, Section 8.3)", "rfc://9110#section-8.3"),
    ])
  func `one document named twice is one citation`(selection: String, expected: String) {
    #expect(CitationLink.link(in: selection)?.appURL.absoluteString == expected)
  }

  /// A comment's prose spells a place in lower case more often than not.
  @Test(
    arguments: [
      ("RFC 9110 section 8.3", "rfc://9110#section-8.3"),
      ("RFC 9110, appendix b", "rfc://9110#appendix-B"),
    ])
  func `a place is read in either case`(selection: String, expected: String) {
    #expect(CitationLink.link(in: selection)?.appURL.absoluteString == expected)
  }

  @Test(
    arguments: [
      "",
      "   ",
      "the request target",
      "§8.3",
      "Section 8.3",
      "9110",
      "RFC 9110 and RFC 9111",
      "RFC 2119 BCP 14",
      "Section 4 and RFC 9110",
      "RFC 9110 is cited in Section 4",
      "Section 8.3 of RFC 9110 ([RFC9110], Section 8.4)",
      "[RFC9110], [RFC9111]",
      "RFCs 9110 and 9111",
      "RFC 9110, Sections 8.3 and 8.4",
      "RFC 9110 §8.3 and §8.4",
      "Section 8.3 of RFC 9110 and Section 4",
      "RFC 9110 and 9111",
      "RFC 9110/9111",
      "RFC 9110, 9111",
      "RFC 9110 and rfc 9111",
      "[RFC9110] and [I-D.ietf-httpbis-semantics]",
      "https://example.com/",
    ])
  func `no single citation makes no link`(selection: String) {
    #expect(CitationLink.link(in: selection) == nil)
  }

  /// Only the citation is replaced: the words the cursor caught around it stay.
  @Test(
    arguments: [
      ("RFC 9110 §8.3", "rfc://9110#section-8.3"),
      (" RFC 9110 §8.3\n", " rfc://9110#section-8.3\n"),
      ("// see RFC 9110 §8.3.", "// see rfc://9110#section-8.3."),
      ("// see §8.3 of RFC 9110.", "// see rfc://9110#section-8.3."),
      ("(RFC 9110, Section 8.3)", "(rfc://9110#section-8.3)"),
      ("per Section 8.3 of [RFC9110], which", "per rfc://9110#section-8.3, which"),
      ("as RFC 9110 (Section 8.3) says", "as rfc://9110#section-8.3 says"),
      ("RFC 9110 (see [RFC9110])", "rfc://9110"),
      ("Section 8.3 of RFC 9110 ([RFC9110]).", "rfc://9110#section-8.3."),
      ("([RFC9110] (RFC 9110))", "(rfc://9110)"),
      ("// BCP 14 ", "// BCP 14 "),
      (" BCP 14\n", " rfc://bcp14\n"),
    ])
  func `a replacement replaces the citation and keeps the rest`(
    selection: String, expected: String
  ) {
    #expect((CitationLink.replacement(for: selection) ?? selection) == expected)
  }

  @Test func `no single citation makes no replacement`() {
    #expect(CitationLink.replacement(for: "RFC 9110 and RFC 9111") == nil)
  }
}
