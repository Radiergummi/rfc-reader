import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A minimal in-memory XML tree. RFC documents are small enough (a few MB at most)
/// that building a tree and walking it is far simpler than a streaming state machine.
struct XMLElement: Sendable {
    var name: String
    var attributes: [String: String]
    var children: [XMLNode]

    init(name: String, attributes: [String: String] = [:], children: [XMLNode] = []) {
        self.name = name
        self.attributes = attributes
        self.children = children
    }

    subscript(attribute: String) -> String? { attributes[attribute] }

    var elements: [XMLElement] {
        children.compactMap {
            if case .element(let element) = $0 { return element }
            return nil
        }
    }

    func first(_ name: String) -> XMLElement? {
        elements.first { $0.name == name }
    }

    func all(_ name: String) -> [XMLElement] {
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

enum XMLNode: Sendable {
    case element(XMLElement)
    case text(String)
}

enum XMLTreeError: Error, Sendable {
    case malformed(line: Int, column: Int, message: String)
    case empty
}

/// Builds an `XMLElement` tree from data using Foundation's `XMLParser`.
final class XMLTreeBuilder: NSObject, XMLParserDelegate {
    private var stack: [XMLElement] = []
    private var root: XMLElement?
    private var pendingText = ""
    private var failure: XMLTreeError?

    static func parse(_ data: Data) throws -> XMLElement {
        let builder = XMLTreeBuilder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        _ = parser.parse()
        // A completed root element is a complete document; errors reported after it are
        // a swift-corelibs-foundation artefact on large inputs, not malformed XML.
        if let root = builder.root { return root }
        if let failure = builder.failure { throw failure }
        if let error = parser.parserError {
            throw XMLTreeError.malformed(
                line: parser.lineNumber, column: parser.columnNumber,
                message: error.localizedDescription
            )
        }
        throw XMLTreeError.empty
    }

    private func flushText() {
        guard !pendingText.isEmpty, !stack.isEmpty else {
            pendingText = ""
            return
        }
        stack[stack.count - 1].children.append(.text(pendingText))
        pendingText = ""
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
        flushText()
        stack.append(XMLElement(name: elementName, attributes: attributeDict))
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        flushText()
        guard let finished = stack.popLast() else { return }
        if stack.isEmpty {
            root = finished
        } else {
            stack[stack.count - 1].children.append(.element(finished))
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        pendingText.append(string)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        pendingText.append(String(decoding: CDATABlock, as: UTF8.self))
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: any Error) {
        failure = .malformed(
            line: parser.lineNumber, column: parser.columnNumber,
            message: parseError.localizedDescription
        )
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
