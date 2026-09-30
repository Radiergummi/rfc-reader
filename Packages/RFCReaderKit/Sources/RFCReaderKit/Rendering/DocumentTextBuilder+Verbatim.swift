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
    let text = displayedText(of: content, indent: indent)
    let scale = monospaceScale(for: text, indent: indent)
    // A rendition's ranges are into the block's own text, so a block shown other
    // than as written (unfolded, #64) is not decorated.
    let rendition =
      text == content.text
      ? ArtworkRenderers.render(
        content, classification,
        context: RenderContext(style: style, column: max(style.indentStep, style.measure - indent)))
      : nil
    let showsSource = choices.shownAsSource.contains(ordinal)
    let shown: VerbatimBox.Shown = rendition == nil ? .plain : showsSource ? .source : .rendered
    let decorated: DecoratedText? =
      if shown == .rendered, case .decorated(let decorated)? = rendition { decorated } else { nil }
    let box = VerbatimBox(
      content, ordinal: ordinal, classification: classification, shown: shown,
      spokenLabel: decorated?.spokenLabel)

    // Before the label, so the label is inside the card it names.
    let start = output.length
    if content.kind == .sourceCode, let type = content.type, !type.isEmpty {
      var label = captionAttributes(paragraphStyle(indent: indent, spacingAfter: 0))
      label[.rfcVerbatim] = box
      append(type.uppercased() + "\n", label)
    }

    let lineHeight = content.kind == .artwork ? style.artworkLineHeightMultiple : nil
    let body = text.hasSuffix("\n") ? text : text + "\n"
    let bodyStart = output.length
    append(
      body,
      [
        .font: style.monospacedFont(scale: scale),
        .foregroundColor: bodyColor,
        .rfcVerbatim: box,
        .paragraphStyle: paragraphStyle(
          indent: indent, spacingAfter: 0, wraps: false, lineHeightMultiple: lineHeight),
      ])
    if let decorated {
      decorate(decorated, from: bodyStart)
    }
    // Every line ends a paragraph, so the spacing that separates the block from what
    // follows goes on its last line alone. On all of them, a figure read double
    // spaced (#31).
    let lastLine = output.mutableString.paragraphRange(
      for: NSRange(location: output.length - 1, length: 0))
    output.addAttribute(
      .paragraphStyle,
      value: paragraphStyle(
        indent: indent, spacingAfter: style.paragraphSpacing, wraps: false,
        lineHeightMultiple: lineHeight),
      range: lastLine)
    decorate(from: start, with: .artwork)
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
  /// sheared (#31). The box keeps the tabs; this is only what is drawn and measured.
  ///
  /// Unfolded before the tabs are expanded: a tab at the start of a continuation is
  /// the author's, which `FoldedLines` keeps, and a tab later in one sits at its
  /// column in the rejoined line, not in the folded one.
  func displayedText(of content: Preformatted, indent: CGFloat) -> String {
    guard
      let unfolded = FoldedLines.unfold(content.text).map(Self.expandingTabsTrimmingTabbedLines),
      monospaceScale(for: unfolded, indent: indent) == 1
    else { return Self.expandingTabsTrimmingTabbedLines(content.text) }
    return unfolded
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
