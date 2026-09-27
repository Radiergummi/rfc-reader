import Foundation

/// A minimal in-memory XML tree. RFC documents are small enough (a few MB at most)
/// that building a tree and walking it is far simpler than a streaming state machine.
///
/// A namespace rather than bare `XMLElement` and `XMLNode`, which shadowed
/// FoundationXML's classes of the same names (#133).
enum XMLTree {
  struct Element: Sendable {
    var name: String
    var attributes: [String: String]
    var children: [Node]

    init(name: String, attributes: [String: String] = [:], children: [Node] = []) {
      self.name = name
      self.attributes = attributes
      self.children = children
    }

    subscript(attribute: String) -> String? { attributes[attribute] }

    var elements: [Element] {
      children.compactMap {
        if case .element(let element) = $0 { return element }
        return nil
      }
    }

    func first(_ name: String) -> Element? {
      elements.first { $0.name == name }
    }

    func all(_ name: String) -> [Element] {
      elements.filter { $0.name == name }
    }

    /// Concatenated text of this element and all descendants.
    var text: String {
      var result = ""
      appendText(to: &result)
      return result
    }

    private func appendText(to result: inout String) {
      for child in children {
        switch child {
        case .text(let text): result.append(text)
        case .element(let element): element.appendText(to: &result)
        }
      }
    }

    /// Text with runs of whitespace collapsed, as a browser would render it.
    var normalizedText: String {
      text.collapsingWhitespace()
    }
  }

  enum Node: Sendable {
    case element(Element)
    case text(String)
  }

  /// The document's root element, built from `XMLDriver`'s events.
  static func parse(_ data: Data) throws(XMLSyntaxError) -> Element {
    let builder = Builder()
    try XMLDriver.run(data, into: builder)
    // The driver returns only once the root has closed, which is when it is set.
    guard let root = builder.root else {
      throw XMLSyntaxError(line: 0, column: 0, message: "empty document")
    }
    return root
  }

  private final class Builder: XMLEvents {
    private var stack: [Element] = []
    private(set) var root: Element?
    private var pendingText = ""

    func start(_ name: String, attributes: [String: String]) {
      flushText()
      stack.append(Element(name: name, attributes: attributes))
    }

    func end(_ name: String) {
      flushText()
      guard let finished = stack.popLast() else { return }
      if stack.isEmpty {
        root = finished
      } else {
        stack[stack.count - 1].children.append(.element(finished))
      }
    }

    func text(_ text: String) {
      pendingText.append(text)
    }

    private func flushText() {
      guard !pendingText.isEmpty, !stack.isEmpty else {
        pendingText = ""
        return
      }
      stack[stack.count - 1].children.append(.text(pendingText))
      pendingText = ""
    }
  }
}

extension String {
  /// Collapses any run of whitespace (including newlines) to a single space and trims the ends.
  func collapsingWhitespace() -> String {
    var result = ""
    result.reserveCapacity(count)
    var previousWasSpace = true
    for scalar in unicodeScalars {
      // XML whitespace is #x20, #x9, #xD and #xA only. U+00A0 and friends are
      // content: collapsing them would undo non-breaking reference labels.
      if scalar == " " || scalar == "\t" || scalar == "\r" || scalar == "\n" {
        if !previousWasSpace { result.append(" ") }
        previousWasSpace = true
      } else {
        result.unicodeScalars.append(scalar)
        previousWasSpace = false
      }
    }
    if result.hasSuffix(" ") { result.removeLast() }
    return result
  }
}
