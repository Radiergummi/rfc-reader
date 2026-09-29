import Foundation

/// One document, ready for a single `NSTextContentStorage`.
///
/// `@unchecked Sendable` so a build can happen off the main actor and the result can
/// cross to it. What licenses it is a handover, not a copy (#128):
///
/// - `text` is the builder's own working buffer, and the builder is local to
///   `DocumentTextBuilder.build`, so nothing that could write it outlives the call.
/// - Every attribute value in it is either immutable — fonts, colours, paragraph
///   styles — or made by that build and held by nothing else: the chips'
///   attachments. Paragraph styles have to be immutable rather than merely
///   unshared, because Foundation uniques equal attribute dictionaries across
///   every string in the process and two builds do end up holding the same ones.
/// - `AnchorIndex` is a `Sendable` value.
///
/// Nothing mutates a `BuiltDocument` after it is constructed; the text view only
/// reads it, and `BuilderHandoverTests` holds each of these to account.
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
