import Foundation
import Testing

@testable import RFCKit

/// Depagination: page headers and footers, running headers, tabs and control bytes.
@Suite("Legacy text parser: page furniture")
struct LegacyTextParserPaginationTests {
  @Test func `strips page furniture`() throws {
    let text = try Fixtures.string("rfc2119.txt")
    let stripped = LegacyTextParser.stripPagination(text)
    #expect(!stripped.contains("[Page 1]"))
    #expect(!stripped.contains("RFC 2119                     RFC Key Words"))
    #expect(!stripped.contains("\u{0C}"))
    #expect(
      stripped.contains("Request for Comments: 2119"),
      "the first-page header block is content, not furniture")
    #expect(stripped.contains("6. Guidance in the use of these Imperatives"))
  }

  /// A tab is eight columns, but `leadingSpaceCount` counted spaces only, so a line
  /// indented with one read as indent 0 (#40). RFC 717 indents a list with tabs
  /// under prose indented six spaces: the block's indent came out as 0, the four
  /// columns its figure shares were never stripped, and the tabs themselves reached
  /// the reader, whose verbatim style sets no tab stops.
  @Test func `tabs are columns before any indent is read`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc717.txt"))
    let artwork = document.artworkText
    #expect(!artwork.contains { $0.contains("\t") }, "a tab survived into artwork")
    #expect(
      !document.allSections.contains { $0.titleText.contains("\t") },
      "a tab survived into a heading")

    let header = try #require(artwork.first { $0.contains("Destination net") })
    let lines = header.split(separator: "\n", omittingEmptySubsequences: false)
    // The block's indent is four, from `    0`, and every line loses exactly that.
    #expect(lines.first == "0           Destination net          (8)")
    #expect(lines.contains("  This field selects the appropriate gateway processing and is used"))
    #expect(lines.contains("    0 -- Escape; protocol is specified by a subsequent field"))
  }

  /// RFC 793 repeats a three-line page header on 62 pages, justified left and right on
  /// facing pages, and it names no RFC, so the running-header pattern never matched it
  /// (#52). Each page then opened with `Transmission Control Protocol` at column 0,
  /// which is a heading: ~33 sections called `Functional Specification`, and every
  /// paragraph that crossed a page break cut in two by one of them.
  @Test func `recurring page headers are furniture not sections`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc793.txt"))
    let furniture = ["Transmission Control Protocol", "Functional Specification", "September 1981"]
    let spurious = document.allSections.filter { furniture.contains($0.titleText) }
    #expect(spurious.isEmpty, "\(spurious.count) sections are page headers")
    // The third line names the section the page is in -- `Introduction` on four
    // pages, `Philosophy` on six -- and each of those sections is already headed
    // `1.  INTRODUCTION`, `2.  PHILOSOPHY`, so none of it is a heading either.
    let unnumbered = document.allSections.filter { $0.number == nil }.map(\.titleText)
    let repeated = Dictionary(grouping: unnumbered, by: \.self).filter { $0.value.count > 1 }.keys
    #expect(repeated.isEmpty, "unnumbered headings that repeat: \(repeated.sorted())")
    #expect(!unnumbered.contains("Philosophy"))

    // With the header gone the page break is only a page break, and the sentence
    // across it is one paragraph again.
    let paragraphs = document.paragraphs.map(\.plainText)
    #expect(
      paragraphs.contains { $0.contains("the TCP must tell user to go into \"normal mode\".") })
  }

  /// A section running header is furniture on every page but the first, where it is
  /// the only thing that says a section starts. RFC 770 heads its bibliography with
  /// a centered `REFERENCES` that is no heading, and a running `References` on each of
  /// its pages; dropping every one of those lost all 58 entries.
  @Test func `a section running header still opens its section`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc770.txt"))
    let lists = document.referenceLists
    #expect(lists.flatMap(\.entries).count == 58)
    #expect(document.allSections.filter { $0.titleText == "References" }.count == 1)
  }

  /// A header that alternates between facing pages is on every other page, so it is
  /// on half of them at most, and just under half where the last pages carry none.
  /// RFC 810 sets `RFC 810 ... 1 March 1982` on its even pages, which the running-header
  /// pattern knows, and `1 March 1982 ... RFC 810` on its odd ones, which it does not:
  /// on three of eight, that header was read as a section's, and its first copy
  /// stayed in the body.
  @Test func `a header on alternate pages names the document`() throws {
    let text = try Fixtures.string("rfc810.txt")
    #expect(
      LegacyTextParser.recurringFurniture(in: text).filter { $0.hasPrefix("1 March 1982") }.count
        == 3)
    let body = LegacyTextParser.stripPagination(text).split(separator: "\n")
    #expect(!body.contains { $0.hasPrefix("1 March 1982") && $0.hasSuffix("RFC 810") })
  }

  /// Only a whole number varies from page to page, so only a whole number is masked
  /// when furniture is compared. RFC 2049 sets one-line anchors in its bibliography
  /// and four of them land at a page edge; masking every digit made `[RFC-1522]` and
  /// `[RFC-1524]` the same line recurring across pages, and both were dropped.
  @Test func `numbers inside a word do not make two lines the same`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc2049.txt"))
    let anchors = document.referenceLists.flatMap { $0.entries.map(\.anchor) }
    #expect(anchors.contains("RFC-1522"))
    #expect(anchors.contains("RFC-1524"))
    #expect(anchors.count == 42)
  }

  /// A line that recurs at page edges is furniture only if it is not also the body's.
  /// RFC 2013 is a MIB module, where every object ends in `STATUS current` and a
  /// `DESCRIPTION`, and those fall within four lines of the foot of three pages; read
  /// as a section running header, every copy after the first was dropped from the
  /// module. A running header sits at the head of its pages, on every page of its
  /// section, set off by a blank line -- and is rarer anywhere else than at the edge.
  @Test func `a line the body repeats is not furniture`() throws {
    let text = try Fixtures.string("rfc2013.txt")
    let document = LegacyTextParser.parse(text)
    func count(_ line: String, in text: String) -> Int {
      text.split(separator: "\n").filter {
        $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") == line
      }.count
    }
    let artwork = document.artworkText.joined(separator: "\n")
    for line in ["STATUS current", "DESCRIPTION"] {
      #expect(count(line, in: artwork) == count(line, in: text), "\(line)")
    }
  }

  /// A section running header belongs to the block that opens its page, directly under
  /// the document's own header. RFC 6208 registers five media types, and each
  /// registration's `Additional information:` falls at the head of a page -- but below
  /// the blank lines the removed `RFC 6208 ... April 2011` leaves, and every copy but
  /// the first was dropped as the running header of a section.
  @Test func `a line below the page header is not a section running header`() throws {
    let text = try Fixtures.string("rfc6208.txt")
    let body = LegacyTextParser.stripPagination(text)
    func count(_ text: String) -> Int {
      text.split(separator: "\n").filter {
        $0.trimmingCharacters(in: .whitespaces) == "Additional information:"
      }.count
    }
    #expect(count(body) == count(text))
    #expect(
      LegacyTextParser.recurringFurniture(in: text).allSatisfy {
        !$0.contains("Additional information:")
      })
  }

  /// Furniture recurs in the same place, so a line at the foot of one page and a line
  /// at the head of the next are not two sightings of it. RFC 1556 cites ISO 8859
  /// parts 6 and 8 as one anchor each, word for word the same up to the part number
  /// on the entry's third line, and the pair straddles a page break.
  @Test func `the same line at opposite edges is not a running header`() throws {
    let document = LegacyTextParser.parse(try Fixtures.string("rfc1556.txt"))
    let labels = document.referenceLists.flatMap { $0.entries.map(\.displayAnchor) }
    #expect(labels.filter { $0 == "ISO-8859" }.count == 2)
    #expect(labels.count == 7)
  }

  @Test func `overstrikes and control bytes are removed`() {
    let bold = "T\u{08}Ta\u{08}ab\u{08}bl\u{08}le\u{08}e"
    let underlined = "_\u{08}R_\u{08}F_\u{08}C"
    #expect(LegacyTextParser.removingControlCharacters(bold) == "Table")
    #expect(LegacyTextParser.removingControlCharacters(underlined) == "RFC")
    #expect(LegacyTextParser.removingControlCharacters("a\u{00}\u{1B}b\tc\u{0C}") == "ab\tc\u{0C}")
    #expect(LegacyTextParser.removingControlCharacters("plain") == "plain")
  }
}
