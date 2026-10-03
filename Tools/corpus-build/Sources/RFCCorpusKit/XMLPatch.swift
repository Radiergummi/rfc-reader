import Foundation

#if canImport(FoundationXML)
  import FoundationXML
#endif

/// A per-document correction to the converter's output, in the format of RFC 5261 (An
/// XML Patch Operations Framework Utilizing XPath Selectors): a `<diff>` of `<add>`,
/// `<replace>` and `<remove>` operations, applied in order, each to the result of the
/// one before (#197).
///
/// Two deviations from the RFC. Selectors are full XPath 1.0, not its restricted
/// subset, so an operation can select by content (`t[starts-with(normalize-space(),
/// '…')]`). And there is no `ws`: the patched document is serialized again, which
/// normalizes whitespace, so it would do nothing.
///
/// Validation is strict. A selector must match exactly one node, as the RFC requires,
/// the node must suit the operation, and an operation element or attribute this does
/// not know is an error, so a typo like `postion=` fails instead of appending.
public struct XMLPatch: Sendable {
  /// What a failure names the patch by, such as `rfc5.xml`.
  public var name: String
  private var operations: [Operation]

  /// One operation, its content kept as text so the patch can cross threads.
  private struct Operation: Sendable {
    var kind: OperationKind
    var selector: String
    var content: [Content]
    /// `remove //section[@anchor='preamble']`, for a failure to name.
    var summary: String
  }

  private enum OperationKind: Sendable {
    case replace
    case remove
    case add(Position)
    case addAttribute(String)
  }

  private enum Position: String, Sendable {
    case append, prepend, before, after
  }

  private enum Content: Sendable {
    case element(String)
    case text(String)
  }

  /// Why a patch could not be read, or where it stopped applying.
  public struct Failure: Error, CustomStringConvertible, Sendable {
    public var patch: String
    /// The operation's place in the patch, from 1; nil when the file itself is wrong.
    public var operation: Int?
    /// The operation's name and selector.
    public var summary: String?
    public var reason: String

    public var description: String {
      guard let operation else { return "\(patch): \(reason)" }
      return "\(patch), operation \(operation) (\(summary ?? "")): \(reason)"
    }
  }

  /// Whether the override `data` is a patch rather than a snapshot: its root is
  /// `<diff>`, or it is not XML at all, which reading it as a patch then reports.
  public static func isPatch(_ data: Data) -> Bool {
    let root = (try? XMLDocument(data: data))?.rootElement()?.name
    return root == nil || root == "diff"
  }

  /// Reads the patch file `data`, named `name` in what fails.
  public init(parsing data: Data, name: String) throws(Failure) {
    self.name = name
    self.operations = []
    func failure(_ reason: String, operation: Int? = nil, summary: String? = nil) -> Failure {
      Failure(patch: name, operation: operation, summary: summary, reason: reason)
    }
    // XMLDocument recovers from what is not well-formed on Linux, where libxml2 drops a
    // bare `&` from a selector and the operation then selects something else.
    // XMLParser refuses it on both platforms.
    let parser = XMLParser(data: data)
    guard parser.parse() else {
      throw failure("not XML: \(parser.parserError.map { "\($0)" } ?? "malformed")")
    }
    let document: XMLDocument
    do {
      document = try XMLDocument(data: data, options: .nodePreserveWhitespace)
    } catch {
      throw failure("not XML: \(error)")
    }
    guard let root = document.rootElement(), root.name == "diff" else {
      throw failure("the root element is not <diff>")
    }
    for child in root.children ?? [] {
      switch child.kind {
      case .comment:
        continue
      case .text where Self.isWhitespace(child.stringValue):
        continue
      case .element:
        guard let element = child as? XMLElement else { continue }
        let number = operations.count + 1
        do {
          operations.append(try Self.operation(element))
        } catch let reason {
          let selector = element.attribute(forName: "sel")?.stringValue ?? ""
          throw failure(
            reason.message, operation: number, summary: "\(element.name ?? "") \(selector)")
        }
      default:
        throw failure("<diff> holds something other than operations")
      }
    }
    guard !operations.isEmpty else { throw failure("<diff> holds no operations") }
  }

  /// What is wrong with one operation element.
  private struct Malformed: Error {
    var message: String
  }

  private static func operation(_ element: XMLElement) throws(Malformed) -> Operation {
    let name = element.name ?? ""
    let allowed: Set<String> =
      switch name {
      case "add": ["sel", "pos", "type"]
      case "replace", "remove": ["sel"]
      default: throw Malformed(message: "<\(name)> is not an operation")
      }
    let attributes = element.attributes ?? []
    for attribute in attributes where !allowed.contains(attribute.name ?? "") {
      throw Malformed(message: "<\(name)> has no attribute \(attribute.name ?? "")")
    }
    guard let selector = element.attribute(forName: "sel")?.stringValue, !selector.isEmpty
    else { throw Malformed(message: "<\(name)> has no sel") }

    var content: [Content] = []
    let children = (element.children ?? []).filter { $0.kind != .comment }
    let holdsElements = children.contains { $0.kind == .element }
    // Nothing but whitespace: an empty operation, laid out over lines.
    let isBlank = children.allSatisfy { $0.kind == .text && isWhitespace($0.stringValue) }
    for child in children {
      switch child.kind {
      case .element:
        // On macOS the whitespace before an element is not a text node but the start
        // of the element's own XML, and parsing that XML alone would drop it.
        let xml = child.xmlString
        let leading = xml.prefix { isWhitespace(String($0)) }
        if !leading.isEmpty { content.append(.text(String(leading))) }
        content.append(.element(String(xml.dropFirst(leading.count))))
      case .text:
        content.append(.text(child.stringValue ?? ""))
      default:
        throw Malformed(message: "<\(name)> holds something other than elements and text")
      }
    }
    // Whitespace between elements may be all that keeps two inline elements' words
    // apart; beside them at the edges, it only lays the patch out.
    if holdsElements {
      while case .text(let text) = content.first, isWhitespace(text) { content.removeFirst() }
      while case .text(let text) = content.last, isWhitespace(text) { content.removeLast() }
    }

    let kind: OperationKind
    switch name {
    case "remove":
      guard isBlank else { throw Malformed(message: "<remove> must be empty") }
      kind = .remove
    case "replace":
      kind = .replace
    default:
      let position = element.attribute(forName: "pos")?.stringValue
      if let type = element.attribute(forName: "type")?.stringValue {
        guard type.hasPrefix("@"), type.count > 1 else {
          throw Malformed(message: "type \(type) is not an attribute, @name")
        }
        guard position == nil else {
          throw Malformed(message: "an attribute has no position")
        }
        guard !holdsElements else { throw Malformed(message: "an attribute's value is text") }
        kind = .addAttribute(String(type.dropFirst()))
      } else {
        guard let parsed = Position(rawValue: position ?? "append") else {
          throw Malformed(message: "pos \(position ?? "") is not append, prepend, before or after")
        }
        guard !isBlank else { throw Malformed(message: "<add> has nothing to add") }
        kind = .add(parsed)
      }
    }
    return Operation(
      kind: kind, selector: selector, content: content, summary: "\(name) \(selector)")
  }

  private static func isWhitespace(_ text: String?) -> Bool {
    (text ?? "").allSatisfy { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }
  }

  /// How many operations the patch holds.
  public var operationCount: Int { operations.count }

  /// Applies every operation to `document`, in order. The first that fails stops the
  /// rest, which would see a tree its author did not intend, and `document` is left
  /// as that operation found it.
  public func apply(to document: XMLDocument) throws(Failure) {
    for index in operations.indices {
      try apply(operation: index + 1, to: document)
    }
  }

  /// Applies the operation `number`, from 1, to `document`.
  public func apply(operation number: Int, to document: XMLDocument) throws(Failure) {
    let operation = operations[number - 1]
    do {
      try Self.apply(operation, to: document)
    } catch let reason {
      throw failure(operation: number, reason.message)
    }
  }

  /// The failure of the operation `number`, from 1, for `reason`.
  public func failure(operation number: Int, _ reason: String) -> Failure {
    Failure(
      patch: name, operation: number, summary: operations[number - 1].summary, reason: reason)
  }

  private static func apply(_ operation: Operation, to document: XMLDocument) throws(Malformed) {
    let matches: [XMLNode]
    do {
      matches = try document.nodes(forXPath: operation.selector)
    } catch {
      throw Malformed(message: "not an XPath selector: \(error)")
    }
    guard matches.count == 1, let target = matches.first else {
      throw Malformed(message: "matched \(matches.count) nodes")
    }

    switch operation.kind {
    case .remove:
      switch target.kind {
      case .attribute:
        if let name = target.name { (target.parent as? XMLElement)?.removeAttribute(forName: name) }
      case .element where target.parent is XMLDocument:
        throw Malformed(message: "the root element cannot be removed")
      case .element, .text:
        target.detach()
      default:
        throw Malformed(message: "only an element, an attribute or a text node is removed")
      }

    case .replace:
      switch target.kind {
      case .element:
        let nodes = try nodes(operation.content)
        guard nodes.count == 1, let replacement = nodes.first as? XMLElement else {
          throw Malformed(message: "an element is replaced by exactly one element")
        }
        if let parent = target.parent as? XMLElement {
          parent.replaceChild(at: target.index, with: replacement)
        } else if target.parent is XMLDocument {
          document.setRootElement(replacement)
        }
      case .attribute:
        target.stringValue = try attributeValue(operation.content)
      case .text:
        target.stringValue = try text(operation.content)
      default:
        throw Malformed(message: "only an element, an attribute or a text node is replaced")
      }

    case .add(let position):
      guard target.kind == .element, let element = target as? XMLElement else {
        throw Malformed(message: "children are added to an element")
      }
      let nodes = try nodes(operation.content)
      switch position {
      case .append:
        for node in nodes { element.addChild(node) }
      case .prepend:
        element.insertChildren(nodes, at: 0)
      case .before, .after:
        guard let parent = element.parent as? XMLElement else {
          throw Malformed(message: "the root element has no siblings")
        }
        parent.insertChildren(nodes, at: element.index + (position == .after ? 1 : 0))
      }

    case .addAttribute(let name):
      guard target.kind == .element, let element = target as? XMLElement else {
        throw Malformed(message: "an attribute is added to an element")
      }
      guard element.attribute(forName: name) == nil else {
        throw Malformed(message: "the element already has \(name); replace it instead")
      }
      let value = try attributeValue(operation.content)
      guard let attribute = XMLNode.attribute(withName: name, stringValue: value) as? XMLNode
      else { throw Malformed(message: "\(name) is not an attribute name") }
      element.addAttribute(attribute)
    }
  }

  /// The content as nodes to insert.
  private static func nodes(_ content: [Content]) throws(Malformed) -> [XMLNode] {
    var nodes: [XMLNode] = []
    for item in content {
      switch item {
      case .element(let xml):
        // `XMLElement(xmlString:)` drops a text node that is only whitespace, such as
        // the space between two inline elements, and runs their words together.
        let document: XMLDocument
        do {
          document = try XMLDocument(xmlString: xml, options: .nodePreserveWhitespace)
        } catch {
          throw Malformed(message: "content does not parse: \(error)")
        }
        guard let element = document.rootElement() else {
          throw Malformed(message: "content is not an element")
        }
        element.detach()
        nodes.append(element)
      case .text(let text):
        if let node = XMLNode.text(withStringValue: text) as? XMLNode { nodes.append(node) }
      }
    }
    return nodes
  }

  /// The content as the text of an attribute or a text node.
  private static func text(_ content: [Content]) throws(Malformed) -> String {
    var text = ""
    for item in content {
      guard case .text(let part) = item else {
        throw Malformed(message: "an attribute or a text node takes text, not an element")
      }
      text += part
    }
    return text
  }

  /// The content as an attribute's value: its text without the whitespace that lays
  /// it out over lines, which the parser would not read.
  private static func attributeValue(_ content: [Content]) throws(Malformed) -> String {
    try text(content).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
