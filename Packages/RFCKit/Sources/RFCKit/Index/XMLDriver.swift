import Foundation

#if canImport(FoundationXML)
  import FoundationXML
#endif

/// Malformed XML, from any of RFCKit's parsers (#133): where, and what the parser
/// said. The one error for it, which each parser's own error wraps.
public struct XMLSyntaxError: Error, LocalizedError, Sendable, Equatable {
  public let line: Int
  public let column: Int
  public let message: String

  public init(line: Int, column: Int, message: String) {
    self.line = line
    self.column = column
    self.message = message
  }

  public var errorDescription: String? {
    "Malformed XML at line \(line), column \(column): \(message)"
  }
}

/// What a parser hears from `XMLDriver`: elements opening and closing, and the text
/// between them, as `XMLParser` reports it.
protocol XMLEvents: AnyObject {
  func start(_ name: String, attributes: [String: String])
  func end(_ name: String)
  func text(_ text: String)
}

/// RFCKit's one owner of `XMLParser` (#133). The tree builder and the streaming index
/// parser both run on it, so they share one reading of the rule that matters most:
///
/// **A document whose root element has closed is complete.** swift-corelibs-foundation
/// reports a parser error after the root closes on large valid inputs; that error is
/// deliberately ignored, not a bug to fix. Anything that goes wrong before the root
/// closes is an `XMLSyntaxError`.
enum XMLDriver {
  static func run(_ data: Data, into events: any XMLEvents) throws(XMLSyntaxError) {
    let delegate = Delegate(events: events)
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    parser.shouldProcessNamespaces = false
    parser.shouldResolveExternalEntities = false
    _ = parser.parse()
    if delegate.rootClosed { return }
    if let failure = delegate.failure { throw failure }
    throw XMLSyntaxError(
      line: parser.lineNumber, column: parser.columnNumber,
      message: parser.parserError?.localizedDescription
        ?? (delegate.depth == 0
          ? "empty document" : "the document ended before its root element closed")
    )
  }

  /// The root element's name and attributes, and nothing after them. A draft's header
  /// is all `DraftHeader` reads, and a v2 draft's DOCTYPE often declares external
  /// entities its body uses. They are never resolved, and a full parse would stop on
  /// them.
  static func rootElement(of data: Data) throws(XMLSyntaxError) -> (
    name: String, attributes: [String: String]
  ) {
    let delegate = RootDelegate()
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    parser.shouldProcessNamespaces = false
    parser.shouldResolveExternalEntities = false
    _ = parser.parse()
    // Stopping at the root is reported as an error; with the root read, it is not one.
    if let root = delegate.root { return root }
    throw XMLSyntaxError(
      line: parser.lineNumber, column: parser.columnNumber,
      message: parser.parserError?.localizedDescription ?? "empty document")
  }

  private final class RootDelegate: NSObject, XMLParserDelegate {
    private(set) var root: (name: String, attributes: [String: String])?

    func parser(
      _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
      qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
      root = (elementName, attributeDict)
      parser.abortParsing()
    }
  }

  private final class Delegate: NSObject, XMLParserDelegate {
    let events: any XMLEvents
    private(set) var depth = 0
    private(set) var rootClosed = false
    private(set) var failure: XMLSyntaxError?

    init(events: any XMLEvents) {
      self.events = events
    }

    func parser(
      _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
      qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
      depth += 1
      events.start(elementName, attributes: attributeDict)
    }

    func parser(
      _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
      qualifiedName qName: String?
    ) {
      events.end(elementName)
      depth -= 1
      if depth == 0 { rootClosed = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
      events.text(string)
    }

    func parser(_ parser: XMLParser, foundCDATA cdataBlock: Data) {
      events.text(String(decoding: cdataBlock, as: UTF8.self))
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: any Error) {
      // Only the first. One reported after the root closes is ignored by `run`.
      guard failure == nil else { return }
      failure = XMLSyntaxError(
        line: parser.lineNumber, column: parser.columnNumber,
        message: parseError.localizedDescription)
    }
  }
}
