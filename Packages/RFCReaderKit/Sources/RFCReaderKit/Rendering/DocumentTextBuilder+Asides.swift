import Foundation
import RFCKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

extension DocumentTextBuilder {
  /// An aside (#700): a card, as a block quote is, that opens with a "Note" caption
  /// of the reader's, the line Implementer folds the aside's body under. Where the
  /// aside's own text opens with that word, it gives way to the caption, so the card
  /// never says it twice. A build with no live links, which is paper, has no
  /// caption, and keeps the aside's words as they are.
  func appendAside(_ blocks: [Block], indent: CGFloat) {
    guard style.emitsLinks else {
      appendDecorated(blocks, decoration: .aside, indent: indent)
      return
    }
    let start = output.length
    let ordinal = nextAsideOrdinal
    nextAsideOrdinal += 1
    let labeled = Self.labeledAside(blocks)
    // A paragraph the label was all of goes, and its anchor lands on the caption.
    mark(labeled.anchor)
    appendAsideCaption(labeled.caption, indent: indent + style.indentStep)
    appendBlocks(labeled.blocks, indent: indent + style.indentStep)
    decorate(from: start, with: .aside)
    // As `decorate` does: a nested aside has claimed its own span already.
    let range = NSRange(location: start, length: output.length - start)
    var gaps: [NSRange] = []
    output.enumerateAttribute(.rfcAside, in: range) { value, subrange, _ in
      if value == nil { gaps.append(subrange) }
    }
    for gap in gaps {
      output.addAttribute(.rfcAside, value: String(ordinal), range: gap)
    }
  }

  /// The caption, a line of its own at the top of the card, small and tracked as a
  /// code block's language is. The reader's, not the document's words: a copied
  /// selection leaves it out, and VoiceOver says the word rather than spelling the
  /// capitals.
  private func appendAsideCaption(_ caption: String, indent: CGFloat) {
    var attributes: [NSAttributedString.Key: Any] = [
      .font: style.codeLabelFont,
      .foregroundColor: RFCColors.secondaryLabel,
      // Set solid: the body's line height would add leading above one short line.
      .paragraphStyle: paragraphStyle(
        indent: indent, spacingAfter: style.paragraphSpacing * 0.4, lineHeightMultiple: 1),
      .rfcReaderOnly: "",
    ]
    let lineBreak = NSAttributedString(string: "\n", attributes: attributes)
    attributes[.kern] = style.codeLabelFont.pointSize * 0.08
    attributes[.rfcSpoken] = caption
    output.append(NSAttributedString(string: caption.uppercased(), attributes: attributes))
    output.append(lineBreak)
  }

  /// An aside as the builder sets it: what its caption says, its blocks, and the
  /// anchor of a paragraph the label was all of, for the caption to carry.
  struct LabeledAside: Equatable {
    var caption = "Note"
    var blocks: [Block]
    var anchor: String?
  }

  /// An aside's caption, and its blocks with the label their text opens with taken
  /// out, if it opens with one: "Note:" or "NOTE:", or "Notes:", which the caption
  /// then says. A paragraph that was only the label goes, and its anchor is kept.
  static func labeledAside(_ blocks: [Block]) -> LabeledAside {
    guard case .paragraph(var paragraph)? = blocks.first,
      let (label, rest) = droppingLabel(paragraph.inlines)
    else { return LabeledAside(blocks: blocks) }
    let caption = label.lowercased().hasPrefix("notes") ? "Notes" : "Note"
    guard !rest.isEmpty else {
      return LabeledAside(
        caption: caption, blocks: Array(blocks.dropFirst()), anchor: paragraph.anchor)
    }
    paragraph.inlines = rest
    return LabeledAside(caption: caption, blocks: [.paragraph(paragraph)] + blocks.dropFirst())
  }

  private static let asideLabels = ["Note:", "NOTE:", "Notes:", "NOTES:"]

  /// `inlines` without the label they open with, and the label; nil where they do
  /// not open with one. A label set in bold or italics goes with its emphasis.
  private static func droppingLabel(_ inlines: [Inline]) -> (label: String, rest: [Inline])? {
    guard let first = inlines.first else { return nil }
    let following = Array(inlines.dropFirst())
    switch first {
    case .text(let text):
      let words = text.drop { $0.isWhitespace }
      guard let label = asideLabels.first(where: { words.hasPrefix($0) }) else { return nil }
      let after = words.dropFirst(label.count)
      return (label, trimmingLeadingWhitespace([.text(String(after))] + following))
    case .strong(let inner), .emphasis(let inner):
      guard let (label, innerRest) = droppingLabel(inner) else { return nil }
      guard !innerRest.isEmpty else { return (label, trimmingLeadingWhitespace(following)) }
      let rest: Inline =
        if case .strong = first { .strong(innerRest) } else { .emphasis(innerRest) }
      return (label, [rest] + following)
    default:
      return nil
    }
  }

  /// `inlines` without the white space and line breaks they open with.
  private static func trimmingLeadingWhitespace(_ inlines: [Inline]) -> [Inline] {
    var inlines = inlines
    while let first = inlines.first {
      switch first {
      case .lineBreak:
        inlines.removeFirst()
      case .text(let text):
        let trimmed = text.drop { $0.isWhitespace }
        guard trimmed.isEmpty else {
          inlines[0] = .text(String(trimmed))
          return inlines
        }
        inlines.removeFirst()
      default:
        return inlines
      }
    }
    return inlines
  }
}
