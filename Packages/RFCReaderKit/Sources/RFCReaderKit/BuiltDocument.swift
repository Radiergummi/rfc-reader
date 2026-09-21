import Foundation

/// One document, ready for a single `NSTextContentStorage`.
///
/// Not `Sendable`: `NSAttributedString` is not, and this never leaves the main actor.
public struct BuiltDocument {
    public let text: NSAttributedString
    public let anchors: AnchorIndex

    public init(text: NSAttributedString, anchors: AnchorIndex) {
        self.text = text
        self.anchors = anchors
    }
}
