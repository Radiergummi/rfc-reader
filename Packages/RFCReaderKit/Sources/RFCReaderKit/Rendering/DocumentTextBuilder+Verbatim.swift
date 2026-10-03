import Foundation
import RFCKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

extension DocumentTextBuilder {
  /// Artwork and source code go into the storage verbatim, non-wrapping, in a
  /// monospace font scaled so the widest line fits the measure.
  ///
  /// Scaled rather than scrolled sideways: the body is one text storage, and no
  /// block of it scrolls on its own. Across the 8,457-document converted corpus,
  /// 97.8% of artwork blocks are 69 columns or narrower and 99.998% are 79 or
  /// narrower; the widest line anywhere is 129 columns, in RFC 2124.
  func appendVerbatim(_ content: Preformatted, indent: CGFloat) {
    mark(content.anchor)
    let ordinal = nextVerbatimOrdinal
    nextVerbatimOrdinal += 1
    let classification = ArtworkClassifier.classify(content, in: documentID, hints: hints)
    // Fitted inside the card's inset on either side: a figure's card hugs it rather
    // than inset it, but the presentation is not known before the text is.
    let fittedIndent = indent + FragmentGeometry.cardInset * 2
    let text = displayedText(of: content, indent: fittedIndent)
    let scale = monospaceScale(for: text, indent: fittedIndent)
    let context = RenderContext(
      style: style, column: max(style.indentStep, style.measure - fittedIndent))
    var shownContent = content
    shownContent.text = text
    let rendered = ArtworkRenderers.render(shownContent, classification, context: context)
    // Tokens are a function of the text alone, so a highlighted block follows the
    // text shown, unfolded (#64) or not. A decoration's ranges are into the grid of
    // the block as written, so a block shown other than as written is not decorated.
    let rendition: Rendition? =
      switch rendered {
      case .decorated? where text != content.text: nil
      default: rendered
      }
    let showsSource =
      choices.presentation(of: PresentationKey(anchor: content.anchor, ordinal: ordinal)) == .text
    // Code is highlighted whatever the choices say: it has no other presentation, and
    // "Draw diagrams" and "Show as Text" are about drawings.
    let shown: VerbatimBox.Shown =
      switch rendition {
      case nil: .plain
      case .styled?: .highlighted
      case .decorated?: showsSource ? .source : .rendered
      }
    let decorated: DecoratedText? =
      if shown == .rendered, case .decorated(let decorated)? = rendition { decorated } else { nil }
    // Shown folded keeps the header, which a block shown unfolded has lost.
    let box = VerbatimBox(
      content, ordinal: ordinal, classification: classification, shown: shown,
      spokenLabel: decorated?.spokenLabel, shownFolding: FoldedLines.strategy(of: text))
    // A figure's card hugs it; every other card's text is set in from its edges.
    let inset = shown.isFigure ? 0 : FragmentGeometry.cardInset

    // Before the label, so the label is inside the card it names.
    let start = output.length
    if content.kind == .sourceCode, let type = content.type, !type.isEmpty {
      appendCodeLabel(type, box: box, indent: indent, inset: inset)
    }

    let labelWidth =
      output.length > start
      ? lineWidth(
        output.attributedSubstring(from: NSRange(location: start, length: output.length - start)))
      : 0
    let lineHeight = content.kind == .artwork ? style.artworkLineHeightMultiple : nil
    // A figure's card ends a padding past its widest line and sits in the middle of
    // the column; every other card spans the column from its indent, as a table's
    // does, its text set in by the card's inset. Through the indent, so selection,
    // find and strokes follow. The scale fitted the block inside the inset, which
    // centering never narrows.
    let contentWidth: CGFloat? =
      shown.isFigure ? max(labelWidth, widestLine(of: text, scale: scale)) : nil
    let bodyIndent =
      contentWidth.map { max(indent, (style.measure - $0) / 2) } ?? indent + inset
    let body = text.hasSuffix("\n") ? text : text + "\n"
    let bodyStart = output.length
    append(
      body,
      [
        .font: style.monospacedFont(scale: scale),
        .foregroundColor: bodyColor,
        .rfcVerbatim: box,
        .paragraphStyle: paragraphStyle(
          indent: bodyIndent, spacingAfter: 0, wraps: false, lineHeightMultiple: lineHeight),
      ])
    if let decorated {
      decorate(decorated, from: bodyStart)
    }
    if style.emitsLinks, AccessibleReading.isDiagram(box) {
      setDiagramSpeech(NSRange(location: bodyStart, length: output.length - bodyStart))
    }
    if shown.isFigure, style.emitsLinks {
      output.addAttribute(
        .rfcFigureItem, value: FigureMenu.itemTag(of: box),
        range: NSRange(location: bodyStart, length: output.length - bodyStart))
    }
    // Every line ends a paragraph, so the spacing that separates the card from what
    // comes before goes on its first line alone, and from what follows on its last.
    // On all of them, a figure read double spaced (#31). The card is drawn inside
    // that spacing (`FragmentGeometry.Placement`), which therefore has room for its
    // padding as well as for the margin a paragraph keeps.
    let margin = FragmentGeometry.cardPadding / 2
    let opensCard = bodyStart == start
    let firstLine = output.mutableString.paragraphRange(
      for: NSRange(location: bodyStart, length: 0))
    let lastLine = output.mutableString.paragraphRange(
      for: NSRange(location: output.length - 1, length: 0))
    func lineStyle(before: CGFloat, after: CGFloat) -> NSParagraphStyle {
      paragraphStyle(
        indent: bodyIndent, spacingBefore: before, spacingAfter: after, wraps: false,
        lineHeightMultiple: lineHeight)
    }
    if opensCard, firstLine != lastLine {
      output.addAttribute(
        .paragraphStyle, value: lineStyle(before: margin, after: 0), range: firstLine)
    }
    output.addAttribute(
      .paragraphStyle,
      value: lineStyle(
        before: opensCard && firstLine == lastLine ? margin : 0,
        after: style.paragraphSpacing + FragmentGeometry.cardPadding * 1.5),
      range: lastLine)
    decorate(from: start, with: .artwork)
    let block = NSRange(location: start, length: output.length - start)
    if let contentWidth {
      output.addAttribute(.rfcContentWidth, value: contentWidth, range: block)
    }
    if inset > 0 {
      output.addAttribute(.rfcCardInset, value: inset, range: block)
    }
    // Last, so no pass above walks the runs the colors cut the block into.
    if case .styled(let tokens)? = rendition {
      highlight(tokens, from: bodyStart)
    }
  }

  /// A code block's language, a line of its own at the card's trailing edge, and on
  /// macOS the button that copies the block after it. The reader's, not the
  /// document's words: a copied selection leaves both out. The line opens the card,
  /// so it carries the margin before it.
  private func appendCodeLabel(
    _ type: String, box: VerbatimBox, indent: CGFloat, inset: CGFloat
  ) {
    let attributes: [NSAttributedString.Key: Any] = [
      .font: style.codeLabelFont,
      .foregroundColor: RFCColors.secondaryLabel,
      .paragraphStyle: paragraphStyle(
        indent: indent + inset, spacingBefore: FragmentGeometry.cardPadding / 2,
        spacingAfter: 0, alignment: .right, trailingIndent: inset),
      .rfcVerbatim: box,
      .rfcReaderOnly: "",
    ]
    var label = attributes
    label[.kern] = style.codeLabelFont.pointSize * 0.08
    let line = NSMutableAttributedString(string: type.uppercased(), attributes: label)
    #if !canImport(UIKit)
      if style.emitsLinks, let button = copyButton(attributes: attributes) {
        line.append(NSAttributedString(string: " ", attributes: attributes))
        line.append(button)
      }
    #endif
    line.append(NSAttributedString(string: "\n", attributes: attributes))
    output.append(line)
  }

  /// What VoiceOver says in place of a diagram's lines, where UIKit reads it: in
  /// the text, since `UITextView` has no per-range accessor to override (#308).
  /// AppKit reads no such key, and `ReaderTextView` says a diagram there itself.
  /// Only in a build for the reader, the one with live links: a printed page is not
  /// read by VoiceOver.
  func setDiagramSpeech(_ body: NSRange) {
    #if canImport(UIKit)
      for line in AccessibleReading.diagramSpeech(ofDiagram: body, in: output.mutableString) {
        output.addAttribute(
          .accessibilitySpeechIPANotation, value: line.pronunciation, range: line.range)
      }
    #endif
  }

  /// Sets a decorated block's strokes on all of it, its ruler in the secondary
  /// color and its border characters in `hiddenColor`. The text is unchanged.
  func decorate(_ decorated: DecoratedText, from bodyStart: Int) {
    let body = NSRange(location: bodyStart, length: output.length - bodyStart)
    output.addAttribute(.rfcStrokes, value: StrokeBox(decorated.strokes), range: body)
    for (ranges, color) in [
      (decorated.secondary, RFCColors.secondaryLabel), (decorated.hidden, Self.hiddenColor),
    ] {
      for range in ranges {
        output.addAttribute(
          .foregroundColor, value: color,
          range: NSRange(location: bodyStart + range.location, length: range.length))
      }
    }
  }

  /// Colors a highlighted block's tokens from the theme. Plain tokens keep the
  /// body color the block was set in, which a quote or an aside sets. The text is
  /// unchanged.
  ///
  /// As few runs as the colors need: white space shows no color, so it joins the
  /// colored run before it, and so does a token of the same color after it. A block
  /// of JSON is otherwise cut into a run for every token and every space between
  /// two, and every later pass over the storage walks them (`Build: RFC 8727` in
  /// `make benchmark`).
  func highlight(_ tokens: [SyntaxToken], from bodyStart: Int) {
    let text = output.mutableString
    var run: (range: NSRange, color: PlatformColor)?
    for token in tokens {
      let range = NSRange(location: bodyStart + token.range.location, length: token.range.length)
      let color = SyntaxTheme.standard.color(for: token.kind)
      if let current = run, color == nil || color === current.color,
        color != nil || Self.isWhitespace(range, in: text)
      {
        run = (
          NSRange(
            location: current.range.location, length: NSMaxRange(range) - current.range.location),
          current.color
        )
        continue
      }
      if let current = run {
        output.addAttribute(.foregroundColor, value: current.color, range: current.range)
      }
      run = color.map { (range, $0) }
    }
    if let current = run {
      output.addAttribute(.foregroundColor, value: current.color, range: current.range)
    }
  }

  private static func isWhitespace(_ range: NSRange, in text: NSString) -> Bool {
    text.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted, range: range)
      .location == NSNotFound
  }

  /// How wide a verbatim block's widest line is set. An ASCII line is its columns at
  /// the monospaced advance, scaled as the block is: the count `monospaceScale`
  /// fits. Any other line is measured, since the font sets a wide character two
  /// columns wide and takes one it lacks from a fallback font, and a card the
  /// columns alone measured would end inside the line.
  func widestLine(of text: String, scale: CGFloat) -> CGFloat {
    let font = style.monospacedFont(scale: scale)
    let widths = text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
      line.allSatisfy(\.isASCII)
        ? CGFloat(line.count) * monospaceAdvance * scale
        : lineWidth(NSAttributedString(string: String(line), attributes: [.font: font]))
    }
    return widths.max() ?? 0
  }

  /// What a verbatim block shows: unfolded, without its header, where RFC 8792
  /// folded it and every unfolded line fits the column at full size; otherwise the
  /// block as published (issue #64).
  ///
  /// The 69-column limit behind the folding is the plain-text page's, not the
  /// reader's, so a column wide enough shows what the author wrote. One that is not
  /// keeps the published folds rather than scaling the unfolded lines down: those
  /// can be far longer than the 129 columns fit-to-measure scaling was measured
  /// against, and a fold the header explains reads better than type too small to
  /// read. The header has to stay with the folds, since it is what explains them.
  ///
  /// Either way its tabs are spaces to the next eighth column, as the RFC Editor's
  /// text rendering sets them: the verbatim style has no tab stops, and a default
  /// stop is a distance in points, not in the block's columns, so a tabbed figure
  /// sheared (#31). The box keeps the tabs; this is what is drawn, measured and
  /// copied (`copiedText(of:)`).
  ///
  /// Unfolded before the tabs are expanded: a tab at the start of a continuation is
  /// the author's, which `FoldedLines` keeps, and a tab later in one sits at its
  /// column in the rejoined line, not in the folded one.
  ///
  /// Source code also loses the indent all its lines share, which the XML of a
  /// converted RFC keeps from the text format, and which sat inside the card's
  /// padding as a second margin. Artwork keeps it, as part of the drawing. Shown
  /// folded, it loses the indent its unfolded lines share, not the folded ones':
  /// `rfcfold` sets the header, and a `'\\'` continuation's backslash, at the first
  /// column whatever the code's indent, and a selection unfolded over the block
  /// would otherwise keep an indent its copy button does not.
  func displayedText(of content: Preformatted, indent: CGFloat) -> String {
    guard let unfolded = FoldedLines.unfold(content.text) else {
      return Self.shown(content.text, kind: content.kind)
    }
    let shownUnfolded = Self.shown(unfolded, kind: content.kind)
    if monospaceScale(for: shownUnfolded, indent: indent) == 1 { return shownUnfolded }
    let folded = Self.expandingTabsTrimmingTabbedLines(content.text)
    guard content.kind == .sourceCode else { return folded }
    let unfoldedIndent = Self.sharedIndent(of: Self.expandingTabsTrimmingTabbedLines(unfolded))
    return Self.removingIndent(unfoldedIndent, from: folded)
  }

  /// The block as copied, by Copy Figure and by a code block's copy button: what a
  /// column wide enough shows, so that a selection over the whole block pastes the
  /// same. Unfolded whatever the column, its tabs expanded, and source code without
  /// the indent its lines share.
  static func copiedText(of content: Preformatted) -> String {
    shown(content.unfoldedText, kind: content.kind)
  }

  /// `text`, a block's or its unfolding, as the reader sets it: tabs expanded, and
  /// for source code the shared indent taken off.
  private static func shown(_ text: String, kind: Preformatted.Kind) -> String {
    let expanded = expandingTabsTrimmingTabbedLines(text)
    return kind == .sourceCode ? removingSharedIndent(expanded) : expanded
  }

  /// `text` less the spaces every line with any text starts with; a line of white
  /// space alone loses as many of its own.
  static func removingSharedIndent(_ text: String) -> String {
    removingIndent(sharedIndent(of: text), from: text)
  }

  /// The number of spaces every line of `text` with any text starts with.
  private static func sharedIndent(of text: String) -> Int {
    text.split(separator: "\n", omittingEmptySubsequences: false)
      .filter { line in line.contains { $0 != " " } }
      .map { line in line.prefix { $0 == " " }.count }
      .min() ?? 0
  }

  /// `text` with up to `indent` leading spaces taken off each line: a line with
  /// fewer loses all its own.
  private static func removingIndent(_ indent: Int, from text: String) -> String {
    guard indent > 0 else { return text }
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    return lines.map { line in
      String(line.dropFirst(min(indent, line.prefix { $0 == " " }.count)))
    }
    .joined(separator: "\n")
  }

  /// Tabs expanded, and a line that had one loses its trailing white space: a tab
  /// that ends a line draws nothing, and expanded it would count up to eight
  /// columns towards the block's width, and so its scale.
  private static func expandingTabsTrimmingTabbedLines(_ text: String) -> String {
    guard text.utf8.contains(9) else { return text }
    return text.split(separator: "\n", omittingEmptySubsequences: false)
      .map { line in
        guard line.utf8.contains(9) else { return String(line) }
        return String(line).expandingTabs().trimmingTrailingWhitespace()
      }
      .joined(separator: "\n")
  }

  /// 1 when the block already fits, otherwise the factor that makes its widest line
  /// fit what the measure leaves after `indent` — never less than one indent step,
  /// or a block nested deep enough to eat the measure would scale to nothing.
  func monospaceScale(for text: String, indent: CGFloat) -> CGFloat {
    let columns =
      text.split(separator: "\n", omittingEmptySubsequences: false).map(\.count).max() ?? 0
    guard columns > 0, monospaceAdvance > 0 else { return 1 }
    return min(
      1, max(style.indentStep, style.measure - indent) / (CGFloat(columns) * monospaceAdvance))
  }
}
