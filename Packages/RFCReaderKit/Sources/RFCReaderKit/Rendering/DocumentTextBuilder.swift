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
  /// The style the *current* region is emitted in. A `var` because a region can be
  /// set quieter than the body around it — see `emitting(in:color:)`.
  private(set) var style: ReadingStyle
  /// The color ordinary prose is emitted in, for the same reason.
  private(set) var bodyColor: PlatformColor
  let output = NSMutableAttributedString()
  var entries: [AnchorIndex.Entry] = []
  /// See `BuiltDocument.keepsWithNext`.
  var keepsWithNext: Set<Int> = []
  /// Which storage characters are which model characters (#522), recorded as the
  /// document is appended; nil until `appendDocument` starts it.
  var positions: PositionMap.Recorder?

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

  /// Whether a section, or the abstract, has been appended, so the next is joined
  /// to it in the model text.
  var hasModelUnit = false

  /// Serial number for the next chip, so no two chip runs carry the same value.
  /// See the chip case in `run(_:base:)`.
  var nextChipID = 0

  /// Rendering an SF Symbol is the expensive part and depends only on which symbol,
  /// its point size and its color, of which a build sees a few — but there is a chip
  /// per cross reference, and RFCs are full of them.
  var chipSymbols: [ChipSymbolKey: PlatformImage] = [:]

  /// A symbol is one of three: a reference chip's, a backlink caption's arrow, or a
  /// code block's copy button.
  struct ChipSymbolKey: Hashable {
    let name: String
    let pointSize: CGFloat
    let color: PlatformColor
  }

  /// The anchors of the document's bibliography entries, which `url(for:)` links
  /// with `ReaderLinkScheme.referenceScheme`. Collected before anything is emitted.
  var referenceAnchors: Set<String> = []

  /// Which kind of list holds each bibliography entry, for whether a citation's
  /// chip is informative. Collected before anything is emitted, as
  /// `referenceAnchors` is.
  var referenceKinds = ReferenceKinds([])

  /// Which sections refer to each section, for the headings' backlink captions. Collected before
  /// anything is emitted, and left empty in a build with no live links: on paper
  /// there is nothing to press.
  var backlinks: [String: [Backlink]] = [:]
  /// The backlinks to use instead of the document's own: a translation's, which are
  /// its original's (#749).
  var givenBacklinks: [String: [Backlink]]?
  /// The errata each heading's chip lists (#387).
  var errata = ErrataMarks.none

  /// The rules the document's grammar blocks define. Collected before anything is
  /// emitted, so a use links to a definition in a later block (#185).
  var grammar = DocumentGrammar()
  /// The rule anchors already emitted: one block repeated word for word would
  /// otherwise define its rules twice.
  var definedRules: Set<String> = []

  /// The document's defined terms, marked at their first use in each paragraph
  /// (#396), and its abbreviations, at their first use in each section (#67). Empty
  /// in a build with no live links: on paper there is no card to show.
  var glossMatcher = GlossMatcher([:])
  /// The terms each paragraph of a definition defines, which it does not mark.
  var ownTerms: [Paragraph: Set<String>] = [:]
  /// The terms already marked in the paragraph being emitted, or nil outside one: a
  /// heading, a table cell, a definition list's term.
  var glossedInParagraph: Set<String>?
  /// The abbreviations already marked in the section being emitted, by short form.
  var glossedInSection: Set<String> = []
  /// Whether the document expands any abbreviation, so a paragraph may.
  var hasAbbreviations = false
  /// The abbreviations the paragraph being emitted expands, which are not marked in
  /// parentheses there.
  var expandedInParagraph: Set<String> = []
  /// Whether the inlines being emitted are a link's, which no gloss goes inside.
  var isInLink = false
  /// Serial number of the last gloss's long-press item, on iOS.
  var nextGlossItem = 0

  /// How far the headings' numbers hang left of the column, and every paragraph is
  /// set in by (`BuiltDocument.sectionNumberHang`). Zero unless the style hangs them.
  var hang: CGFloat = 0

  /// Which blocks the reader asked to see as their source.
  let choices: PresentationChoices
  /// Reviewed verdicts on artwork types, for `ArtworkClassifier`.
  let hints: ArtworkHints
  /// The document being built, for its hints. Set by `appendDocument`.
  var documentID: DocumentID?
  /// The ordinal the next verbatim block gets.
  var nextVerbatimOrdinal = 0
  /// The ordinal the next aside gets (`.rfcAside`).
  var nextAsideOrdinal = 0

  /// The color of a character a decorated block draws over instead of showing.
  public static let hiddenColor = PlatformColor.clear

  /// The words the builder writes into the body itself: English, or a
  /// translation's (#749).
  let labels: DocumentLabels

  init(
    style: ReadingStyle, choices: PresentationChoices = .defaults,
    hints: ArtworkHints = .bundled, labels: DocumentLabels = .english
  ) {
    self.style = style
    self.choices = choices
    self.hints = hints
    self.labels = labels
    bodyColor = Self.labelColor(in: style)
  }

  /// Body text's color: the page theme's on screen, the system's on paper
  /// (`ReadingStyle.followsPageTheme`). The builder's every label-colored run is
  /// this, never `RFCColors.label` directly.
  var labelColor: PlatformColor { Self.labelColor(in: style) }

  private static func labelColor(in style: ReadingStyle) -> PlatformColor {
    style.followsPageTheme ? ReaderPalette.themedText : RFCColors.label
  }

  /// Quieter text's color, as `labelColor` is body text's.
  var secondaryLabelColor: PlatformColor {
    style.followsPageTheme ? ReaderPalette.themedSecondaryText : RFCColors.secondaryLabel
  }

  /// - Parameter title: a title block to open the text with. The reader has none —
  ///   its title is the header view above the text — but a printed page has nothing
  ///   above the text, so a print passes one (#375).
  /// - Parameter choices: the blocks the reader asked to see as their source.
  /// - Parameter hints: reviewed artwork types; tests pass their own.
  /// - Parameters:
  ///   - errata: the errata to mark after the headings (#387); only a build for the
  ///     reader has them.
  ///   - translation: for a translated document (#749), the labels its translation
  ///     gave; nil for the original, which is English throughout.
  public static func build(
    _ document: RFCDocument, style: ReadingStyle, title: TitleBlock? = nil,
    choices: PresentationChoices = .defaults, hints: ArtworkHints = .bundled,
    errata: ErrataMarks = .none, translation: DocumentLabels? = nil
  ) -> BuiltDocument {
    let builder = DocumentTextBuilder(
      style: style, choices: choices, hints: hints, labels: translation ?? .english)
    builder.errata = errata
    return build(document, title: title, translation: translation, with: builder)
  }

  /// A translated document's build (#749), in its labels, with the original's
  /// backlinks: a reference the translation lost the words of is still one the
  /// section makes.
  public static func build(
    _ translated: TranslatedDocument, style: ReadingStyle,
    choices: PresentationChoices = .defaults, hints: ArtworkHints = .bundled,
    errata: ErrataMarks = .none
  ) -> BuiltDocument {
    let builder = DocumentTextBuilder(
      style: style, choices: choices, hints: hints, labels: translated.labels)
    builder.givenBacklinks = translated.backlinks
    builder.errata = errata
    return build(
      translated.document, title: nil, translation: translated.labels, with: builder)
  }

  private static func build(
    _ document: RFCDocument, title: TitleBlock?, translation: DocumentLabels?,
    with builder: DocumentTextBuilder
  ) -> BuiltDocument {
    // In an autorelease pool of its own: a build runs off the main actor, where what
    // it autoreleases was not drained when it ended, so every document opened left
    // a build's worth behind. A run of builds in an `@concurrent` function shows it
    // in the process's footprint (#853).
    autoreleasepool {
      if builder.style.emitsLinks {
        builder.hang = builder.style.sectionNumberHang
      }
      if let title { builder.appendTitle(title) }
      builder.appendDocument(document)
      builder.setDecoratedLinesOnWholePoints()
      reserveChipPadding(in: builder.output)
      // Last: it carries the decorations, indents, insets and widths set so far, and
      // nothing rewrites them after it.
      builder.setDecorationFacts()
      // Handed over, not copied: `builder` ends here, so nothing is left that could
      // write `output` once the result leaves this function. A copy would also be
      // shallow, sharing every attribute value with the original, so it protected
      // nothing and cost a pass over the whole text. See `BuiltDocument`.
      return BuiltDocument(
        text: builder.output, anchors: AnchorIndex(builder.entries),
        keepsWithNext: builder.keepsWithNext, backlinks: builder.backlinks,
        grammar: builder.grammar.withoutParsedBlocks,
        sectionNumberHang: builder.hang, errata: builder.errata, translation: translation,
        positions: builder.positions?.map ?? .empty)
    }
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
  func mark(_ anchor: String?, heading: String? = nil, place: String? = nil, depth: Int? = nil) {
    guard let anchor, !anchor.isEmpty else { return }
    entries.append(
      AnchorIndex.Entry(
        anchor: anchor, offset: output.length, heading: heading, place: place, depth: depth))
  }

  func append(_ string: String, _ attributes: [NSAttributedString.Key: Any]) {
    output.append(NSAttributedString(string: string, attributes: attributes))
  }

  /// Appends `runs`, whose text is the model text's next (#522): inline runs, whose
  /// only characters of their own are a chip's attachment and word joiner.
  func appendModel(_ runs: NSAttributedString) {
    let start = output.length
    output.append(runs)
    positions?.advance(output.mutableString, range: NSRange(location: start, length: runs.length))
  }

  /// The join the model text has here, between two elements (`ModelText`).
  func joinModel() {
    positions?.join(storage: output.mutableString)
  }

  /// Model text this build does not show, at the cursor.
  func skipModel(_ length: Int) {
    positions?.skip(length)
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
        .foregroundColor: labelColor,
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
          .foregroundColor: secondaryLabelColor,
          .paragraphStyle: paragraphStyle(spacingAfter: isLast ? style.paragraphSpacing * 2 : 0),
        ])
    }
  }

  func appendDocument(_ document: RFCDocument) {
    documentID = document.header.id
    // A translation's sentences are not the original's, so it places no highlight
    // and records no map (#749, #522).
    if givenBacklinks == nil {
      positions = PositionMap.Recorder(model: ModelText(document))
    }
    let bibliography = ReferenceGroup.groups(in: document)
    referenceKinds = ReferenceKinds(bibliography)
    referenceAnchors = Set(bibliography.flatMap { $0.entries.map(\.anchor) })
    grammar = DocumentGrammar(of: document, hints: hints)
    if style.emitsLinks {
      backlinks = givenBacklinks ?? Backlinks.within(document)
      glossMatcher = GlossMatcher(document.definedTerms, abbreviations: document.abbreviations)
      hasAbbreviations = !document.abbreviations.isEmpty
      for term in document.definedTerms.values {
        for case .paragraph(let paragraph) in term.definition.flattened {
          ownTerms[paragraph, default: []].insert(term.term)
        }
      }
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
    glossedInSection = []
    hasModelUnit = true
    mark(Self.abstractAnchor)
    keepsWithNext.insert(output.length)
    append(labels.abstract + "\n", headingAttributes(depth: 1, anchor: Self.abstractAnchor))
    // Emitted quiet, rather than emitted and then quietened. A post-pass has to
    // guess which runs "count" — matching against a dynamic color to find the
    // ones to step back — and anything the builder *measures* against the style
    // (artwork's `monospaceScale`, a table's column widths) would be measured at
    // full size and shrunk afterwards, which is a different answer.
    emitting(in: style.scaled(by: Self.abstractScale), color: secondaryLabelColor) {
      appendBlocks(blocks, indent: 0)
    }
  }

  /// A heading at `depth`, carrying the anchor it is the heading of. The abstract's
  /// has nothing above it, being the first thing in the storage; a section's is set
  /// off from the prose before it by `spacingBefore`, and from what follows by
  /// `spacingAfter`, the usual gap unless given.
  ///
  /// One that `hangsNumber` starts at the container's edge, left of the column by
  /// the hang, with a tab to the number's end and another to the column's edge,
  /// where the title starts and a wrapped title's lines go on (#433).
  private func headingAttributes(
    depth: Int, anchor: String, spacingBefore: CGFloat = 0, spacingAfter: CGFloat? = nil,
    hangsNumber: Bool = false
  ) -> [NSAttributedString.Key: Any] {
    let spacingAfter = spacingAfter ?? style.paragraphSpacing * 0.6
    let paragraphStyle =
      hangsNumber
      ? paragraphStyle(
        firstLineIndent: -hang, spacingBefore: spacingBefore, spacingAfter: spacingAfter,
        tabStops: [
          NSTextTab(textAlignment: .right, location: -SectionNumberHang.gap(style: style)),
          NSTextTab(textAlignment: .left, location: 0),
        ])
      : paragraphStyle(spacingBefore: spacingBefore, spacingAfter: spacingAfter)
    return [
      .font: style.headingFont(depth: depth),
      .foregroundColor: labelColor,
      .rfcAnchor: anchor,
      .paragraphStyle: paragraphStyle,
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
    defer {
      self.style = outerStyle
      bodyColor = outerColor
    }
    self.style = style
    bodyColor = color
    body()
  }

  /// `Section.numberPrefix`, with an appendix's word in the labels' language.
  private func numberPrefix(of section: Section) -> String {
    let prefix = section.numberPrefix
    let english = section.appendixWord.label
    guard section.isAppendix, prefix.hasPrefix(english) else { return prefix }
    let word = section.appendixWord == .annex ? labels.annex : labels.appendix
    return word + prefix.dropFirst(english.count)
  }

  private func appendSection(_ section: Section, depth: Int) {
    // The bibliography is not part of the reading flow: every citation in the
    // prose already links straight to the document it names, so the section is
    // several screens of rows nobody reads in order. It lives in the inspector's
    // References tab instead — `DocumentInspector` in the app — and is skipped
    // here, heading and all, rather than left behind as an empty "9. References".
    guard !section.holdsOnlyReferences else { return }
    glossedInSection = []
    // The model text sets a section apart from what came before by a join that
    // belongs to no anchor, and starts it where its span does: a build that drifted
    // from the model text in the section before is back on it here.
    if hasModelUnit { joinModel() }
    hasModelUnit = true
    if let start = positions?.model.span(of: section.anchor)?.range.lowerBound {
      positions?.cursor = start
    }
    let numberPrefix = numberPrefix(of: section)
    mark(
      section.anchor, heading: numberPrefix + section.headingWords.plainText, place: section.place,
      depth: depth)
    keepsWithNext.insert(output.length)
    // Through the same inline path as prose, because a heading cites documents
    // the same way -- "8. Changes from [RFC 3066]". Everything the heading needs
    // is in `base`, so the anchor, the font and the spacing carry across the
    // reference's own runs.
    let citing = backlinks[section.anchor]
    let hangingNumber = hang > 0 ? section.number : nil
    // A backlink caption under the heading takes over the space after it, and
    // the heading keeps only enough to sit close above the caption it belongs to.
    let attributes = headingAttributes(
      depth: depth, anchor: section.anchor, spacingBefore: style.paragraphSpacing * 1.6,
      spacingAfter: citing == nil ? nil : style.paragraphSpacing * 0.15,
      hangsNumber: hangingNumber != nil)
    // The number and an appendix's qualifier are the reader's to compose; the
    // model text of a heading is its title alone.
    let qualifierWords =
      section.qualifier == nil ? "" : Array(section.headingWords.prefix(1)).plainText
    if let hangingNumber {
      appendHangingNumber(
        hangingNumber, of: section.anchor, copiedAs: numberPrefix, attributes: attributes)
    }
    let lead = (hangingNumber == nil ? numberPrefix : "") + qualifierWords
    if !lead.isEmpty {
      output.append(inlineRuns([.text(lead)], base: attributes))
    }
    appendModel(inlineRuns(section.title, base: attributes))
    if let marked = errata.bySection[section.anchor], !marked.isEmpty {
      output.append(errataChip(section.anchor, items: marked, base: attributes))
    }
    append("\n", attributes)
    joinModel()
    if let citing {
      output.append(backlinkCaption(section.anchor, count: citing.count))
    }
    appendBlocks(section.blocks, indent: 0)
    for subsection in section.subsections {
      appendSection(subsection, depth: depth + 1)
    }
  }

  /// A heading's number in the gutter (#433), between the two tabs its paragraph
  /// sets: quieter than the title, and a link to its own heading, which the text
  /// view follows as it follows any anchor, and which Option-click copies. A copy
  /// of it is `copiedAs`, the prefix the heading reads with inline, not its tabs.
  private func appendHangingNumber(
    _ number: String, of anchor: String, copiedAs: String,
    attributes: [NSAttributedString.Key: Any]
  ) {
    var tab = attributes
    tab[.rfcCopiedAs] = copiedAs
    var numberAttributes = tab
    numberAttributes[.foregroundColor] = secondaryLabelColor
    numberAttributes[.rfcSectionNumber] = anchor
    numberAttributes[.link] = ReaderLinkScheme.url(anchor, scheme: ReaderLinkScheme.anchorScheme)
    append("\t", tab)
    append(number, numberAttributes)
    append("\t", tab)
  }

  func appendBlocks(_ blocks: [Block], indent: CGFloat) {
    var isFirst = true
    for block in blocks {
      // A bibliography's list is no part of the model text, so no join comes before it.
      if case .references = block { continue }
      if !isFirst { joinModel() }
      isFirst = false
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
        appendAside(inner, indent: indent)
      case .references:
        // Skipped: see `holdsOnlyReferences`. A `.references` block outside a
        // bibliography section would land here, and is still not body prose.
        continue
      case .index(let index):
        appendBlocks(Self.plainBlocks(of: index), indent: indent)
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
    // A term defined here is not marked here: its definition is what a card would show.
    glossedInParagraph = glossMatcher.isEmpty ? nil : ownTerms[paragraph] ?? []
    if glossedInParagraph != nil, hasAbbreviations {
      expandedInParagraph = Abbreviation.shortForms(expandedIn: paragraph.plainText)
    }
    appendModel(inlineRuns(paragraph.inlines, base: attributes))
    glossedInParagraph = nil
    expandedInParagraph = []
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
      .foregroundColor: secondaryLabelColor,
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
    lineHeightMultiple: CGFloat? = nil,
    trailingIndent: CGFloat = 0
  ) -> NSParagraphStyle {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    // Negative: measured in from the container's trailing edge.
    paragraph.tailIndent = -trailingIndent
    // Every indent and tab stop is measured from the column's edge, which is `hang`
    // in from the container's (#433).
    paragraph.firstLineHeadIndent = hang + (firstLineIndent ?? indent)
    paragraph.headIndent = hang + indent
    paragraph.paragraphSpacingBefore = spacingBefore
    paragraph.paragraphSpacing = spacingAfter
    paragraph.lineHeightMultiple = lineHeightMultiple ?? style.lineHeightMultiple
    paragraph.lineBreakMode = wraps ? .byWordWrapping : .byClipping
    if let tabStops {
      paragraph.tabStops = tabStops.map { stop in
        NSTextTab(
          textAlignment: stop.alignment, location: hang + stop.location, options: stop.options)
      }
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
