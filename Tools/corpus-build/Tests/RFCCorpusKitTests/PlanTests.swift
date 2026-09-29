import Foundation
import RFCCorpusKit
import RFCKit
import Testing

/// What `fetch` downloads and what `convert` takes from `--in`.
@Suite("Plans")
struct PlanTests {
  private static func index() throws -> RFCIndex {
    try RFCIndexParser.parse(contentsOf: Fixtures.url("rfc-index-sample.xml"))
  }

  /// The two formats partition the index, so the two fetches never write the same file.
  @Test func `fetch splits the index by whether an RFC has XML`() throws {
    let index = try Self.index()
    let text = FetchPlan.wanted(in: index, format: .text, limit: nil).map(\.number)
    let xml = FetchPlan.wanted(in: index, format: .xml, limit: nil).map(\.number)
    #expect(text == [1149, 2119, 2818, 5234, 7231, 8174])
    #expect(xml == [8999, 9000, 9110])
  }

  /// The text of the RFCs that have XML: the half the ordinary text fetch skips,
  /// because xml2rfc generated it, fetched for `score` (#42).
  @Test func `the paired text is the text of every RFC with XML`() throws {
    #expect(
      FetchPlan.pairedText(in: try Self.index(), limit: nil).map(\.number) == [8999, 9000, 9110])
  }

  @Test func `fetch takes the first documents up to the limit`() throws {
    let text = FetchPlan.wanted(in: try Self.index(), format: .text, limit: 2).map(\.number)
    #expect(text == [1149, 2119])
  }

  /// In document order, not the directory's: rfc10 after rfc9, not after rfc1.
  @Test func `conversion takes the text files in document order`() throws {
    let names = ["rfc10.txt", "rfc9.txt", "rfc1.txt", "rfc2.xml", ".DS_Store"]
    #expect(try ConversionPlan.files(in: names) == ["rfc1.txt", "rfc9.txt", "rfc10.txt"])
  }

  @Test func `only takes the named numbers`() throws {
    let names = ["rfc10.txt", "rfc9.txt", "rfc1.txt"]
    #expect(try ConversionPlan.files(in: names, only: [10, 1]) == ["rfc1.txt", "rfc10.txt"])
  }

  /// A number asked for by name is expected to be converted; one with no text fails the
  /// run rather than being skipped.
  @Test func `only fails on a number with no text`() {
    #expect {
      try ConversionPlan.files(in: ["rfc1.txt"], only: [1, 99999, 5])
    } throws: { error in
      (error as? ConversionPlan.MissingText)?.numbers == [5, 99999]
    }
  }
}
