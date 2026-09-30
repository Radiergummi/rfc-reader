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
    // An empty document is said as one on both platforms: Darwin reports it only in
    // `parserError`, and swift-corelibs-foundation may report it as text with no
    // element in it.
    if let failure = delegate.failure, !data.isEmpty { throw failure }
    // Not `parserError`: the error left there once `parse()` gives up is a generic
    // one, 111, and the one for an empty document is 1, an internal error.
    throw XMLSyntaxError(
      line: parser.lineNumber, column: parser.columnNumber,
      message: delegate.depth == 0
        ? "empty document" : "the document ended before its root element closed")
  }

  /// What went wrong, in words (#320). Neither platform's error says so itself: its
  /// description is its domain and code, "The operation couldn't be completed.
  /// (NSXMLParserErrorDomain error 76.)". Darwin keeps libxml2's own words in the
  /// error's `userInfo`, swift-corelibs-foundation keeps none, so the code is what
  /// both have, and it is read the same on both. libxml2's words stand in for a code
  /// this does not name, and the code itself for one that has neither. libxml2 says
  /// 5 for input that ends early whether or not a root has opened, so the caller
  /// says which.
  static func message(for error: any Error, rootOpened: Bool) -> String {
    let error = error as NSError
    if error.code == 5, !rootOpened { return "the document ended before its root element opened" }
    if let text = description(ofLibxml2Error: error.code) { return text }
    if let text = error.userInfo["NSXMLParserErrorMessage"] as? String {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { return trimmed }
    }
    return "malformed XML (error \(error.code))"
  }

  /// The errors a document fetched in place of an RFC, or cut short, runs into, by
  /// libxml2's `xmlParserErrors` number, which both platforms report as the error's
  /// code. Not through `XMLParser.ErrorCode`: Darwin's cases carry libxml2's numbers,
  /// but swift-corelibs-foundation numbers its own from 0, so the same code names
  /// another case there.
  private static func description(ofLibxml2Error code: Int) -> String? {
    switch code {
    case 3: "no root element where the document starts"
    // What libxml2 reports for text that is no XML at all; an empty `Data` reports
    // nothing, and is `run`'s own "empty document".
    case 4: "no XML element where the document starts"
    case 5: "the document ended before its root element closed"
    case 9: "a character XML does not allow"
    case 26: "an entity that is not declared"
    case 38: "a < inside an attribute value"
    case 39: "an attribute value without its opening quote"
    case 40: "an attribute value without its closing quote"
    case 41: "an attribute without a value"
    case 64: "an XML declaration that is not at the start"
    case 72: "a tag without its opening <"
    case 73: "a tag without its closing >"
    case 76: "an end tag that does not match the element it closes"
    case 77: "a tag that is not finished"
    case 85: "elements that are not properly nested"
    default: nil
    }
  }

  /// The root element's attributes, and nothing after them. A draft's header
  /// is all `DraftHeader` reads, and a v2 draft's DOCTYPE often declares external
  /// entities its body uses. They are never resolved, and a full parse would stop on
  /// them.
  ///
  /// A root that is not `name` is an error: an error page served in place of the
  /// document parses as far as its root too.
  static func rootAttributes(
    of data: Data, named name: String
  ) throws(XMLSyntaxError) -> [String: String] {
    let delegate = RootDelegate()
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    parser.shouldProcessNamespaces = false
    parser.shouldResolveExternalEntities = false
    _ = parser.parse()
    // Stopping at the root is reported as an error; with the root read, it is not one.
    if let root = delegate.root {
      if root.name == name { return root.attributes }
      throw XMLSyntaxError(
        line: parser.lineNumber, column: parser.columnNumber,
        message: "the root element is <\(root.name)>, not <\(name)>")
    }
    // As in `run`: an empty document is said as one on both platforms.
    if let failure = delegate.failure, !data.isEmpty { throw failure }
    throw XMLSyntaxError(
      line: parser.lineNumber, column: parser.columnNumber, message: "empty document")
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

    /// What went wrong before a root was found: a plain-text error page, a broken
    /// prolog. Not the error aborting reports, which comes after the root.
    private(set) var failure: XMLSyntaxError?

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: any Error) {
      guard root == nil, failure == nil else { return }
      failure = XMLSyntaxError(
        line: parser.lineNumber, column: parser.columnNumber,
        message: XMLDriver.message(for: parseError, rootOpened: false))
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
        message: XMLDriver.message(for: parseError, rootOpened: depth > 0 || rootClosed))
    }
  }
}
