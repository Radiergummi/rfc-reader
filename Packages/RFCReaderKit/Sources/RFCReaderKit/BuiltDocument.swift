import Foundation
import RFCKit

/// One document, ready for an `NSTextContentStorage`.
///
/// `@unchecked Sendable` so a build can happen off the main actor and the result can
/// cross to it. What licenses it is a handover, not a copy (#128):
///
/// - `text` is the builder's own working buffer, and the builder is local to
///   `DocumentTextBuilder.build`, so nothing that could write it outlives the call.
/// - Every attribute value in it is either immutable — fonts, colours, paragraph
///   styles — or made by that build: the chips' attachments. Paragraph styles have
///   to be immutable rather than merely unshared, because Foundation uniques equal
///   attribute dictionaries across every string in the process and two builds do
///   end up holding the same ones.
/// - `AnchorIndex` is a `Sendable` value.
///
/// Once handed over, a build may be installed more than once: a force-click
/// preview keeps its builds, and a repeated preview installs the same one into a
/// new text view (#374). `install` copies the text but not the attribute values, so
/// every storage it goes into holds the build's own attachments. That is sound for
/// two reasons: the builds are kept on the main actor, where the text views are, so
/// nothing crosses a thread after the handover; and no text view writes to what it
/// is given.
///
/// Nothing mutates a `BuiltDocument` after it is constructed, and
/// `BuilderHandoverTests` holds each of these to account, the last by laying one
/// build out and drawing it in two text views.
public struct BuiltDocument: @unchecked Sendable {
  public let text: NSAttributedString
  public let anchors: AnchorIndex
  /// Where every paragraph starts that belongs with the one after it — the title,
  /// the headings, the abstract's — as UTF-16 offsets into `text`. A page never
  /// ends on one (`PrintPagination`). Recorded by the builder as it emits them,
  /// so a new kind of heading is kept with its text where it is written.
  public let keepsWithNext: Set<Int>

  public init(text: NSAttributedString, anchors: AnchorIndex, keepsWithNext: Set<Int> = []) {
    self.text = text
    self.anchors = anchors
    self.keepsWithNext = keepsWithNext
  }
}

/// What a build is a build of: a document, in a style. A build for any other size,
/// column, line height, text size or link style is a different one.
public struct BuildKey: Hashable, Sendable {
  public let document: DocumentID
  public let style: ReadingStyle

  public init(document: DocumentID, style: ReadingStyle) {
    self.document = document
    self.style = style
  }
}
