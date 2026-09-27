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

  @Test func `a document that ends before its root closes is malformed, with where`() {
    do {
      _ = try XMLTree.parse(Data("<a>\n<b>".utf8))
      Issue.record("expected a syntax error")
    } catch {
      #expect(error.line >= 1)
      #expect(!error.message.isEmpty)
      #expect(error.errorDescription?.contains("line \(error.line)") == true)
    }
  }

  @Test func `an empty document is malformed`() {
    #expect(throws: XMLSyntaxError.self) {
      _ = try XMLTree.parse(Data())
    }
  }

  @Test func `every parser reports malformed XML as the same error`() throws {
    let truncated = Data("<rfc><front>".utf8)
    do {
      _ = try RFCXMLParser.parse(truncated)
      Issue.record("expected malformed")
    } catch {
      guard case .malformed(let syntax) = error else {
        Issue.record("\(error) is not malformed")
        return
      }
      #expect(!syntax.message.isEmpty)
    }

    do {
      _ = try RFCIndexParser.parse(Data("<rfc-index><rfc-entry>".utf8))
      Issue.record("expected malformed")
    } catch {
      guard case .malformed = error else {
        Issue.record("\(error) is not malformed")
        return
      }
    }

    do {
      _ = try RecentFeedParser.parse(Data("<rss><channel>".utf8))
      Issue.record("expected malformed")
    } catch {
      guard case .malformed = error else {
        Issue.record("\(error) is not malformed")
        return
      }
    }
  }

  @Test func `a well-formed document that is not an RFC says so`() {
    do {
      _ = try RFCXMLParser.parse(Data("<html/>".utf8))
      Issue.record("expected notAnRFC")
    } catch {
      guard case .notAnRFC(let root) = error else {
        Issue.record("\(error) is not notAnRFC")
        return
      }
      #expect(root == "html")
    }
  }
}
