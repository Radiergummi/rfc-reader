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

  @Test func `an empty document is malformed`() throws {
    let error = try #require(throws: XMLSyntaxError.self) {
      _ = try XMLTree.parse(Data())
    }
    #expect(error.message == "empty document")
  }

  /// In words, the same on both platforms, rather than the error's domain and code,
  /// "The operation couldn't be completed. (NSXMLParserErrorDomain error 76.)" (#320).
  @Test func `the message says what the parser found`() throws {
    let error = try #require(throws: XMLSyntaxError.self) {
      _ = try XMLTree.parse(Data("<a><b></a>".utf8))
    }
    #expect(error.message == "an end tag that does not match the element it closes")
  }

  /// A plain-text error page served in place of a draft fails before any root, and
  /// says why rather than "empty document".
  @Test func `the root of a document that is not XML says why it is missing`() throws {
    let error = try #require(throws: XMLSyntaxError.self) {
      _ = try XMLDriver.rootAttributes(of: Data("404 Not Found".utf8), named: "rfc")
    }
    #expect(error.message == "no XML element where the document starts")
  }

  /// The root's reader says an empty document is one, as `run` does, on both
  /// platforms.
  @Test func `the root of an empty document says it is empty`() throws {
    let error = try #require(throws: XMLSyntaxError.self) {
      _ = try XMLDriver.rootAttributes(of: Data(), named: "rfc")
    }
    #expect(error.message == "empty document")
  }

  /// A body too short for Darwin's parser to report anything is still not empty, and
  /// one of only whitespace is, whatever its length, through both entry points.
  @Test func `only a blank document says it is empty`() throws {
    for (body, expected) in [
      ("OK\n", "no XML element where the document starts"),
      ("  \n\n  \n", "empty document"),
    ] {
      let data = Data(body.utf8)
      let tree = try #require(throws: XMLSyntaxError.self) {
        _ = try XMLTree.parse(data)
      }
      let root = try #require(throws: XMLSyntaxError.self) {
        _ = try XMLDriver.rootAttributes(of: data, named: "rfc")
      }
      #expect(tree.message == expected)
      #expect(root.message == expected)
    }
  }

  /// libxml2 reports the same code, 5, for a document cut short in its prolog as for
  /// one cut short inside its root; the message tells them apart.
  @Test func `a document that ends in its prolog says no root opened`() throws {
    let prolog = Data("<?xml version=\"1.0\"?>\n<!-- a comment -->".utf8)
    let tree = try #require(throws: XMLSyntaxError.self) {
      _ = try XMLTree.parse(prolog)
    }
    let root = try #require(throws: XMLSyntaxError.self) {
      _ = try XMLDriver.rootAttributes(of: prolog, named: "rfc")
    }
    #expect(tree.message == "the document ended before its root element opened")
    #expect(root.message == "the document ended before its root element opened")
  }

  /// A code the driver does not name keeps its number, which is still something to
  /// go on in a bug report.
  @Test func `an error the driver does not name keeps its code`() {
    let error = NSError(domain: "NSXMLParserErrorDomain", code: 99_999)
    #expect(XMLDriver.message(for: error, rootOpened: true) == "malformed XML (error 99999)")
  }

  /// Every error that wraps the syntax error says what it says: the app shows
  /// `localizedDescription`, which for an error that is not `LocalizedError` is its
  /// type's name and a number (#320).
  @Test func `a wrapped syntax error keeps its description`() throws {
    let truncated = Data("<rfc>\n<front>".utf8)
    let expected = try #require(throws: XMLSyntaxError.self) {
      _ = try XMLTree.parse(truncated)
    }
    let wrapped: [any Error] = [
      RFCXMLParser.ParseError.malformed(expected),
      RFCIndexParser.ParseError.malformed(expected),
      RecentFeedParser.ParseError.malformed(expected),
      IANARegistry.ParseError.malformed(expected),
    ]
    for error in wrapped {
      #expect(error.localizedDescription == expected.errorDescription)
    }
    let decoding = RFCEditorClient.ClientError.decoding(
      context: "rfc-index.xml", underlying: RFCIndexParser.ParseError.malformed(expected))
    #expect(decoding.localizedDescription == "rfc-index.xml: \(expected.errorDescription ?? "")")
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
