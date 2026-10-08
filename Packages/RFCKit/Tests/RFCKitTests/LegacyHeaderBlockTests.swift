import Foundation
import Testing

@testable import RFCKit

/// The header block of a legacy title page, read without the index (#767): what the
/// app shows until an index entry is there, and what a draft's text shows. Guard-level,
/// over hand-written lines in the shape of a title page.
@Suite("Legacy text parser: the header block")
struct LegacyHeaderBlockTests {
  /// An author whose left column ran out stands alone at the right of its line, and
  /// is the right column, not the left.
  @Test func `an author alone on a line is an author`() {
    let header = LegacyTextParser.parseFrontMatter([
      "Network Working Group                                          A. Author",
      "Request for Comments: 9999                                     B. Writer",
      "                                                                C. Third",
      "Category: Informational                                       March 1999",
    ])
    #expect(header.authors.map(\.name) == ["A. Author", "B. Writer", "C. Third"])
    #expect(header.id == .rfc(9999))
  }

  /// A list that runs on continues on the next line, indented under its label.
  @Test func `an obsoletes list continued on the next line is read whole`() {
    let header = LegacyTextParser.parseFrontMatter([
      "Network Working Group                                          A. Author",
      "Request for Comments: 9999                                    March 1999",
      "Obsoletes: 1000, 1001,",
      "           1002",
      "Category: Standards Track",
    ])
    #expect(header.obsoletes == [.rfc(1000), .rfc(1001), .rfc(1002)])
    #expect(header.authors.map(\.name) == ["A. Author"])
  }

  /// A number after a series label is the series', not an RFC: `BCP 14` is not RFC 14.
  @Test func `a number in a series is not an RFC`() {
    let header = LegacyTextParser.parseFrontMatter([
      "Network Working Group                                          A. Author",
      "Request for Comments: 9999                                    March 1999",
      "Updates: BCP 14, 2000",
    ])
    #expect(header.updates == [.rfc(2000)])
  }

  /// Older headers write the number after a `#`.
  @Test func `a number after a hash is read`() {
    let header = LegacyTextParser.parseFrontMatter([
      "Network Working Group                                          A. Author",
      "Request for Comments: 999                                       May 1980",
      "Obsoletes: RFC #700",
    ])
    #expect(header.obsoletes == [.rfc(700)])
  }
}
