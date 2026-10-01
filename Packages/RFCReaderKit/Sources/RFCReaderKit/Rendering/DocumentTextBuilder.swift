import CoreText
import Foundation
import RFCKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// Turns an `RFCDocument` into one attributed string plus an anchor index.
///
/// Pure: no view, no state that outlives a build, no I/O — string assembly, `CTLine`
/// measurement and paragraph styles. Deliberately not main-actor bound: a build costs
/// hundreds of milliseconds on the largest RFCs, and blocking the main thread for it
/// is what made the font-size slider feel dead. Handing the finished document to a
/// text view is the only part that needs the main actor, and `BuiltDocument` carries
/// the result across.
public final class DocumentTextBuilder {
  /// The private URL scheme an in-document anchor link uses.
  public static let anchorScheme = "rfc-anchor"

  /// The scheme a citation of a bibliography entry uses instead. The body leaves
  /// the bibliography to the inspector (`holdsOnlyReferences`), so a citation of
  /// anything but an RFC — still an anchor after parsing — has no position to
  /// scroll to, and goes to its entry there.
  public static let referenceScheme = "rfc-reference"

  /// The scheme of a heading's backlink chip (#183), naming the section: a click
  /// lists the sections that refer to it rather than going anywhere.
  public static let backlinksScheme = "rfc-backlinks"

  /// The style the *current* region is emitted in. A `var` because a region can be
  /// set quieter than the body around it — see `emitting(in:color:)`.
  private(set) var style: ReadingStyle
  /// The color ordinary prose is emitted in, for the same reason.
  private(set) var bodyColor: PlatformColor = RFCColors.label
  let output = NSMutableAttributedString()
  var entries: [AnchorIndex.Entry] = []
  /// See `BuiltDocument.keepsWithNext`.
  var keepsWithNext: Set<Int> = []

  /// The advance of one unscaled monospaced character, per body size. It depends
  /// only on the style, and a document can hold hundreds of artwork blocks, each of
  /// which would otherwise build a font and a `CTLine` to ask the same question
  /// again. Keyed rather than computed once, because a region emitted in a quieter
  /// style must be measured in that style too.
  private var monospaceAdvances: [CGFloat: CGFloat] = [:]

  var monospaceAdvance: CGFloat {
    if let cached = monospaceAdvances[style.bodySize] { return cached }
    let advance = lineWidth("0", font: style.monospacedFont(scale: 1))
    monospaceAdvances[style.bodySize] = advance
    return advance
  }

  /// Serial number for the next chip, so no two chip runs carry the same value.
  /// See the chip case in `run(_:base:)`.
  var nextChipID = 0

  /// Rendering an SF Symbol is the expensive part and depends only on which symbol
  /// and the point size, of which a build sees a few — but there is a chip per cross
  /// reference, and RFCs are full of them.
  var chipSymbols: [ChipSymbolKey: PlatformImage] = [:]

  /// A chip's symbol is one of two: a reference's, or a backlink chip's.
  struct ChipSymbolKey: Hashable {
    let name: String
    let pointSize: CGFloat
  }

  /// The anchors of the document's bibliography entries, which `url(for:)` links
  /// with `referenceScheme`. Collected before anything is emitted.
  var referenceAnchors: Set<String> = []

  /// Which kind of list holds each bibliography entry, for whether a citation's
  /// chip is informative. Collected before anything is emitted, as
  /// `referenceAnchors` is.
  var referenceKinds = ReferenceKinds([])

  /// Which sections refer to each section, for the headings' chips. Collected before
  /// anything is emitted, and left empty in a build with no live links: on paper
  /// there is nothing to press.
  var backlinks: [String: [Backlink]] = [:]

  /// Which blocks the reader asked to see as their source.
  let choices: PresentationChoices
  /// Reviewed verdicts on artwork types, for `ArtworkClassifier`.
  let hints: ArtworkHints
  /// The document being built, for its hints. Set by `appendDocument`.
  var documentID: DocumentID?
  /// The ordinal the next verbatim block gets.
  var nextVerbatimOrdinal = 0

  /// The color of a character a decorated block draws over instead of showing.
  public static let hiddenColor = PlatformColor.clear

  init(
    style: ReadingStyle, choices: PresentationChoices = .defaults,
    hints: ArtworkHints = .bundled
  ) {
    self.style = style
    self.choices = choices
    self.hints = hints
  }

  /// - Parameter title: a title block to open the text with. The reader has none —
  ///   its title is the header view above the text — but a printed page has nothing
  ///   above the text, so a print passes one (#375).
  /// - Parameter choices: the blocks the reader asked to see as their source.
  /// - Parameter hints: reviewed artwork types; tests pass their own.
  public static func build(
    _ document: RFCDocument, style: ReadingStyle, title: TitleBlock? = nil,
    choices: PresentationChoices = .defaults, hints: ArtworkHints = .bundled
  ) -> BuiltDocument {
    let builder = DocumentTextBuilder(style: style, choices: choices, hints: hints)
    if let title { builder.appendTitle(title) }
    builder.appendDocument(document)
    builder.setDecoratedLinesOnWholePoints()
    reserveChipPadding(in: builder.output)
    // Handed over, not copied: `builder` ends here, so nothing is left that could
    // write `output` once the result leaves this function. A copy would also be
    // shallow, sharing every attribute value with the original, so it protected
    // nothing and cost a pass over the whole text. See `BuiltDocument`.
    return BuiltDocument(
      text: builder.output, anchors: AnchorIndex(builder.entries),
      keepsWithNext: builder.keepsWithNext, backlinks: builder.backlinks)
  }

  /// Records where an anchor lands. Called immediately before the run it names.
  ///
  /// A `heading` marks the anchors section tracking may report. The index covers
  /// every anchor — paragraphs, figures, tables, reference rows — because
  /// `scroll(to:)` has to reach all of them, but every consumer of the reader's
  /// visible anchor resolves it with `RFCDocument.section(anchor:)`, so reporting a
  /// paragraph anchor would silently break all of them. Only `appendSection` passes
  /// one, which is the one place that knows, and passes the section's `place` with
  /// it.
  func mark(_ anchor: String?, heading: String? = nil, place: String? = nil) {
    guard let anchor, !anchor.isEmpty else { return }
    entries.append(
      AnchorIndex.Entry(anchor: anchor, offset: output.length, heading: heading, place: place))
  }

  func append(_ string: String, _ attributes: [NSAttributedString.Key: Any]) {
    output.append(NSAttributedString(string: string, attributes: attributes))
  }

  /// The width of `string` set as one line in `font`.
  func lineWidth(_ string: String, font: PlatformFont) -> CGFloat {
    lineWidth(NSAttributedString(string: string, attributes: [.font: font]))
  }

  /// The width of `text` set as one line, in the fonts its runs carry, via CoreText
  /// rather than `NSAttributedString.size()`. NSStringDrawing applies line-breaking
  /// and drawing-context layout semantics that are the wrong tool for measuring a
  /// single line, and under CPU load it has been observed to raise an uncaught
  /// `NSException`; a `CTLine`'s typographic bounds answer the same question
  /// directly, without going through a drawing context at all.
  ///
  /// An attachment measures nothing here, and a chip's padding kern is added only
  /// once the build is done, so a chip is measured narrower than it is drawn; a
  /// table cell adds both before it measures, in `cellWidth`.
  func lineWidth(_ text: NSAttributedString) -> CGFloat {
    Self.lineWidth(text)
  }

  /// The same, where there is no builder: `StrokeGeometry` measures a column as the
  /// builder does.
  static func lineWidth(_ text: NSAttributedString) -> CGFloat {
    let line = CTLineCreateWithAttributedString(text)
    return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
  }

}

extension DocumentTextBuilder {
  /// The document's title and the lines under it, as text at the top of the storage
  /// rather than a view over it: what the reader's header view shows, for a page
  /// that has no header view (#375).
  public struct TitleBlock: Sendable, Equatable {
    public let title: String
    /// Set smaller and quieter, a line each: identity, date, authors.
    public let details: [String]
  }

  /// The title's size against the body's: as large on paper as a large title is
  /// against the body on screen.
  static let titleScale: CGFloat = 2

  func appendTitle(_ title: TitleBlock) {
    let details = title.details.filter { !$0.isEmpty }
    keepsWithNext.insert(output.length)
    append(
      title.title + "\n",
      [
        .font: PlatformFont.systemFont(ofSize: style.bodySize * Self.titleScale, weight: .semibold),
        .foregroundColor: RFCColors.label,
        .paragraphStyle: paragraphStyle(
          spacingAfter: style.paragraphSpacing * (details.isEmpty ? 2 : 0.6),
          lineHeightMultiple: 1),
      ].merging(Self.headingLevel(depth: 1)) { current, _ in current })
    for (index, detail) in details.enumerated() {
      let isLast = index == details.count - 1
      append(
        detail + "\n",
        [
          .font: style.captionFont,
          .foregroundColor: RFCColors.secondaryLabel,
          .paragraphStyle: paragraphStyle(spacingAfter: isLast ? style.paragraphSpacing * 2 : 0),
        ])
    }
  }

  func appendDocument(_ document: RFCDocument) {
    documentID = document.header.id
    let bibliography = ReferenceGroup.groups(in: document)
    referenceKinds = ReferenceKinds(bibliography)
    referenceAnchors = Set(bibliography.flatMap { $0.entries.map(\.anchor) })
    if style.emitsLinks {
      backlinks = Backlinks.within(document)
    }
    appendAbstract(document.header.abstract)
    for section in document.sections {
      appendSection(section, depth: 1)
    }
  }

  /// The abstract is the first prose in the storage, and its heading belongs here
  /// with it: neither parser keeps "Abstract" as a block — both consume it into
  /// `DocumentHeader.abstract` — and the reader's header view stops above the
  /// status banner, so a label placed there would sit on the wrong side of it.
  ///
  /// It is anchored and marked like every other heading. It is not a `Section`, so
  /// it is not a section entry in the index and section tracking will not report
  /// it — but the VoiceOver headings rotor and `rfc-anchor:abstract` reach it by
  /// the ordinary rule rather than needing an exception each.
  static let abstractAnchor = "abstract"

  private func appendAbstract(_ blocks: [Block]) {
    guard !blocks.isEmpty else { return }
    mark(Self.abstractAnchor)
    keepsWithNext.insert(output.length)
    append("Abstract\n", headingAttributes(depth: 1, anchor: Self.abstractAnchor))
    // Emitted quiet, rather than emitted and then quietened. A post-pass has to
    // guess which runs "count" — matching against a dynamic color to find the
    // ones to step back — and anything the builder *measures* against the style
    // (artwork's `monospaceScale`, a table's column widths) would be measured at
    // full size and shrunk afterwards, which is a different answer.
    emitting(in: style.scaled(by: Self.abstractScale), color: RFCColors.secondaryLabel) {
      appendBlocks(blocks, indent: 0)
    }
  }

  /// A heading at `depth`, carrying the anchor it is the heading of. The abstract's
  /// has nothing above it, being the first thing in the storage; a section's is set
  /// off from the prose before it by `spacingBefore`.
  private func headingAttributes(depth: Int, anchor: String, spacingBefore: CGFloat = 0)
    -> [NSAttributedString.Key: Any]
  {
    [
      .font: style.headingFont(depth: depth),
      .foregroundColor: RFCColors.label,
      .rfcAnchor: anchor,
      .paragraphStyle: paragraphStyle(
        spacingBefore: spacingBefore, spacingAfter: style.paragraphSpacing * 0.6),
    ].merging(Self.headingLevel(depth: depth)) { current, _ in current }
  }

  /// A heading's level, in the text itself, where UIKit looks for it: that is what
  /// gives `UITextView`'s own heading navigation something to move between, beside
  /// the custom rotor that `.rfcAnchor` feeds. AppKit reads no such key.
  static func headingLevel(depth: Int) -> [NSAttributedString.Key: Any] {
    #if canImport(UIKit)
      [.accessibilityTextHeadingLevel: min(depth, 6)]
    #else
      [:]
    #endif
  }

  /// The abstract introduces the document rather than being part of it, so it is
  /// set a little smaller and in the secondary color.
  static let abstractScale: CGFloat = 0.94

  /// Emits `body` in a different style and color, restoring both afterwards.
  private func emitting(in style: ReadingStyle, color: PlatformColor, _ body: () -> Void) {
    let outerStyle = self.style
    let outerColor = bodyColor
    self.style = style
    bodyColor = color
    body()
    self.style = outerStyle
    bodyColor = outerColor
  }

  private func appendSection(_ section: Section, depth: Int) {
    // The bibliography is not part of the reading flow: every citation in the
    // prose already links straight to the document it names, so the section is
    // several screens of rows nobody reads in order. It lives in the inspector's
    // References tab instead — `DocumentInspector` in the app — and is skipped
    // here, heading and all, rather than left behind as an empty "9. References".
    guard !section.holdsOnlyReferences else { return }
    mark(section.anchor, heading: section.displayTitle, place: section.place)
    keepsWithNext.insert(output.length)
    // Through the same inline path as prose, because a heading cites documents
    // the same way -- "8. Changes from [RFC 3066]". Everything the heading needs
    // is in `base`, so the anchor, the font and the spacing carry across the
    // reference's own runs and the chip is set at heading size.
    let attributes = headingAttributes(
      depth: depth, anchor: section.anchor, spacingBefore: style.paragraphSpacing * 1.6)
    output.append(inlineRuns(section.displayTitleInlines, base: attributes))
    if let citing = backlinks[section.anchor] {
      output.append(backlinkChip(section.anchor, count: citing.count, base: attributes))
      // Nor is the line break after the chip the heading's, or the heading's run
      // would resume on it: a second stop in the headings rotor, on an empty line.
      append("\n", Self.outsideHeading(attributes))
    } else {
      append("\n", attributes)
    }
    appendBlocks(section.blocks, indent: 0)
    for subsection in section.subsections {
      appendSection(subsection, depth: depth + 1)
    }
  }

  func appendBlocks(_ blocks: [Block], indent: CGFloat) {
    for block in blocks {
      switch block {
      case .paragraph(let paragraph):
        appendParagraph(paragraph, indent: indent)
      case .list(let list):
        appendList(list, indent: indent)
      case .definitionList(let list):
        appendDefinitionList(list, indent: indent)
      case .preformatted(let content):
        appendVerbatim(content, indent: indent)
      case .table(let table):
        appendTable(table, indent: indent)
      case .figure(let figure):
        appendFigure(figure, indent: indent)
      case .blockQuote(let inner):
        appendDecorated(inner, decoration: .blockQuote, indent: indent)
      case .aside(let inner):
        appendDecorated(inner, decoration: .aside, indent: indent)
      case .references:
        // Skipped: see `holdsOnlyReferences`. A `.references` block outside a
        // bibliography section would land here, and is still not body prose.
        continue
      }
    }
  }

  /// How many characters of an author's `<t indent>` make one of our indent steps.
  /// Three is the width RFCXML hangs a list item's text at, and a list's text sits
  /// one step in, so a note set in by three under a list lines up with the items'
  /// text here the way it does in the 72-column rendering.
  static let charactersPerIndentStep = 3

  /// The deepest an author's indent sets a paragraph in, in steps. Nine characters
  /// is the most any RFC from 8650 to 10050 asks for, and it is three steps; an
  /// indent past that is kept at three, because every step comes off the column,
  /// and a phone's column is not wide enough to give away more of it.
  static let maximumAuthoredIndentSteps = 3

  /// An author's indent, in whole steps. Characters are the 72-column rendering's
  /// unit and mean nothing in a proportional font; what an indent says here is that
  /// a paragraph belongs under what precedes it, and our lists, definitions and
  /// quotes all say that in whole steps. A fraction of one would sit just off the
  /// text of the list it belongs to -- RFC 8907 sets its status explanations in by
  /// four -- so the count rounds to the nearest step, and any indent at all is at
  /// least one, or `indent="1"` would be dropped on the way.
  static func authoredIndentSteps(forCharacters characters: Int) -> Int {
    guard characters > 0 else { return 0 }
    let nearest = (characters + charactersPerIndentStep / 2) / charactersPerIndentStep
    return min(max(nearest, 1), maximumAuthoredIndentSteps)
  }

  func appendParagraph(_ paragraph: Paragraph, indent: CGFloat) {
    let authoredSteps = CGFloat(Self.authoredIndentSteps(forCharacters: paragraph.indent))
    appendParagraph(
      paragraph, attributes: bodyAttributes(indent: indent + authoredSteps * style.indentStep))
  }

  /// A paragraph set in `attributes`: its anchor where its text starts, its text,
  /// and the newline that ends it. A list item's first paragraph comes here
  /// directly, set on the marker's line in the list's attributes.
  func appendParagraph(_ paragraph: Paragraph, attributes: [NSAttributedString.Key: Any]) {
    mark(paragraph.anchor)
    output.append(inlineRuns(paragraph.inlines, base: attributes))
    append("\n", attributes)
  }

  func bodyAttributes(indent: CGFloat) -> [NSAttributedString.Key: Any] {
    bodyAttributes(paragraphStyle(indent: indent, spacingAfter: style.paragraphSpacing))
  }

  /// Body text, in the body font and the color of the text being emitted, set in
  /// `paragraphStyle`.
  func bodyAttributes(_ paragraphStyle: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
    [.font: style.bodyFont, .foregroundColor: bodyColor, .paragraphStyle: paragraphStyle]
  }

  /// Secondary text that names a block -- a figure's or table's caption, a source
  /// code block's language -- in the caption font and the secondary color.
  func captionAttributes(_ paragraphStyle: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
    [
      .font: style.captionFont,
      .foregroundColor: RFCColors.secondaryLabel,
      .paragraphStyle: paragraphStyle,
    ]
  }

  func paragraphStyle(
    indent: CGFloat = 0,
    firstLineIndent: CGFloat? = nil,
    spacingBefore: CGFloat = 0,
    spacingAfter: CGFloat,
    tabStops: [NSTextTab]? = nil,
    wraps: Bool = true,
    alignment: NSTextAlignment = .natural,
    lineHeightMultiple: CGFloat? = nil
  ) -> NSParagraphStyle {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.firstLineHeadIndent = firstLineIndent ?? indent
    paragraph.headIndent = indent
    paragraph.paragraphSpacingBefore = spacingBefore
    paragraph.paragraphSpacing = spacingAfter
    paragraph.lineHeightMultiple = lineHeightMultiple ?? style.lineHeightMultiple
    paragraph.lineBreakMode = wraps ? .byWordWrapping : .byClipping
    if let tabStops {
      paragraph.tabStops = tabStops
      paragraph.defaultTabInterval = style.indentStep
    }
    // An immutable copy, not the mutable object typed as immutable: Foundation
    // uniques equal attribute dictionaries across every string in the process, so
    // this object may end up shared with another build's text — one being read on
    // the main actor while this build runs. That is only safe if nothing can write
    // it. See `BuiltDocument`.
    // swiftlint:disable:next force_cast
    return paragraph.copy() as! NSParagraphStyle
  }
}
