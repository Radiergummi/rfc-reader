import Foundation

/// One document, ready for a single `NSTextContentStorage`.
///
/// `@unchecked Sendable` so a build can happen off the main actor and the result can
/// cross to it. The invariant that licenses it: `text` is a genuinely immutable
/// `NSAttributedString` — `DocumentTextBuilder.build` copies its mutable working
/// buffer on the way out, so no reference to a mutable instance escapes — and
/// `AnchorIndex` is a `Sendable` value. Nothing mutates a `BuiltDocument` after it
/// is constructed; the text view only reads it.
public struct BuiltDocument: @unchecked Sendable {
    public let text: NSAttributedString
    public let anchors: AnchorIndex

    public init(text: NSAttributedString, anchors: AnchorIndex) {
        self.text = text
        self.anchors = anchors
    }
}
