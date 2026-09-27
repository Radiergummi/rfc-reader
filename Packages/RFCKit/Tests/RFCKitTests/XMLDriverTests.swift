import Foundation
import Testing

@testable import RFCKit

/// The one XML front end (#133): a single driver owns `XMLParser` and the rule that
/// a document whose root element has closed is complete, and every parser reports
/// malformed XML as the same `XMLSyntaxError`.
@Suite("XML front end")
struct XMLDriverTests {
  /// swift-corelibs-foundation reports a parser error after the root element closes
  /// on large valid inputs. The same shape, reproducible anywhere: content after the
  /// root, which `XMLParser` reports only once the root is done. Deliberately
  /// ignored — the document is complete — and pinned so nobody "fixes" it.
  @Test func `an error reported after the root closes is ignored`() throws {
    let tree = try XMLTree.parse(Data("<a><b/></a><trailing".utf8))
    #expect(tree.name == "a")
    #expect(tree.elements.map(\.name) == ["b"])
  }

  /// The index parser streams rather than building a tree, and follows the same rule
  /// because it runs on the same driver.
  @Test func `the index parser follows the same rule`() throws {
    let index = try RFCIndexParser.parse(Data("<rfc-index></rfc-index><trailing".utf8))
    #expect(index.rfcs.isEmpty)
  }

  @Test func `a document that ends before its root closes is malformed, with where`() throws {
    let error = try #require(throws: XMLSyntaxError.self) {
      _ = try XMLTree.parse(Data("<a>\n<b>".utf8))
    }
    #expect(error.line >= 1)
    #expect(!error.message.isEmpty)
    #expect(error.errorDescription?.contains("line \(error.line)") == true)
  }

  @Test func `an empty document is malformed`() {
    #expect(throws: XMLSyntaxError.self) {
      _ = try XMLTree.parse(Data())
    }
  }

  /// The same truncated input through each parser: each wraps exactly the error the
  /// driver reports for it, line, column and message.
  @Test func `every parser reports malformed XML as the same error`() throws {
    let truncated = Data("<rfc>\n<front>".utf8)
    let expected = try #require(throws: XMLSyntaxError.self) {
      _ = try XMLTree.parse(truncated)
    }
    #expect(throws: RFCXMLParser.ParseError.malformed(expected)) {
      _ = try RFCXMLParser.parse(truncated)
    }
    #expect(throws: RFCIndexParser.ParseError.malformed(expected)) {
      _ = try RFCIndexParser.parse(truncated)
    }
    #expect(throws: RecentFeedParser.ParseError.malformed(expected)) {
      _ = try RecentFeedParser.parse(truncated)
    }
  }

  @Test func `a well-formed document that is not an RFC says so`() {
    #expect(throws: RFCXMLParser.ParseError.notAnRFC(rootElement: "html")) {
      _ = try RFCXMLParser.parse(Data("<html/>".utf8))
    }
  }
}
