import Foundation
import RFCKit

/// One document, ready for an `NSTextContentStorage`.
///
/// `@unchecked Sendable` so a build can happen off the main actor and the result can
/// cross to it. What licenses it is a handover, not a copy (#128):
///
/// - `text` is the builder's own working buffer, and the builder is local to
///   `DocumentTextBuilder.build`, so nothing that could write it outlives the call.
/// - Every attribute value in it is either immutable — fonts, colors, paragraph
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
  /// Which sections refer to each section, as the headings' captions count them;
  /// empty in a build with no live links, which has no captions.
  public let backlinks: [String: [Backlink]]
  /// The rules the document's grammar blocks define, for what a rule link previews
  /// (#185).
  public let grammar: DocumentGrammar
  /// Where the document's index is, for the overlays over it; empty without one.
  public let indexMap: IndexMap

  public init(
    text: NSAttributedString, anchors: AnchorIndex, keepsWithNext: Set<Int> = [],
    backlinks: [String: [Backlink]] = [:], grammar: DocumentGrammar = DocumentGrammar(),
    indexMap: IndexMap = .empty
  ) {
    self.text = text
    self.anchors = anchors
    self.keepsWithNext = keepsWithNext
    self.backlinks = backlinks
    self.grammar = grammar
    self.indexMap = indexMap
  }

  /// What a heading's backlink caption lists (#183): the sections that refer to the
  /// one at `anchor`, in document order, each by its heading as the reader draws it.
  public func backlinks(of anchor: String) -> [BacklinkEntry] {
    (backlinks[anchor] ?? []).compactMap { backlink in
      guard let section = backlink.section else {
        return BacklinkEntry(
          anchor: DocumentTextBuilder.abstractAnchor, heading: "Abstract", count: backlink.count)
      }
      guard let heading = anchors.heading(of: section) else { return nil }
      return BacklinkEntry(anchor: section, heading: heading, count: backlink.count)
    }
  }
}

/// A section that refers to another, as a backlink caption lists it.
public struct BacklinkEntry: Sendable, Hashable {
  /// Where following the entry scrolls to.
  public let anchor: String
  public let heading: String
  /// How many times the section refers there.
  public let count: Int

  public init(anchor: String, heading: String, count: Int) {
    self.anchor = anchor
    self.heading = heading
    self.count = count
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

extension BuiltDocument {
  /// The sections of `document` this build holds, in the document's order: what the
  /// contents panel lists (#599). Read off the index the builder emitted rather than
  /// worked out again from the model — "is this a bibliography?" — so the two cannot
  /// disagree, and a row without an anchor would be one the reader cannot scroll to.
  public func reachableSections(of document: RFCDocument) -> [Section] {
    document.allSections.filter { anchors.sections.offset(of: $0.anchor) != nil }
  }
}
