import Foundation
import RFCKit

extension DocumentTextBuilder {
  func appendFigure(_ figure: Figure, indent: CGFloat) {
    mark(figure.anchor)
    let start = output.length
    appendBlocks(figure.blocks, indent: indent)
    let caption = Self.caption("Figure", number: figure.number, title: figure.title)
    // Tag any artwork the figure just contributed with the caption, so the
    // accessibility element has a name even when `Preformatted.name` is absent.
    if let caption {
      let range = NSRange(location: start, length: output.length - start)
      output.enumerateAttribute(.rfcVerbatim, in: range) { value, subrange, _ in
        guard value != nil else { return }
        output.addAttribute(.rfcCaption, value: caption, range: subrange)
      }
    }
    appendCaption(caption, indent: indent)
  }

  /// The rule and the background are drawn by `RFCTextLayoutFragment`; the builder
  /// only says which decoration applies and how far the text is indented.
  func appendDecorated(_ blocks: [Block], decoration: RFCDecoration, indent: CGFloat) {
    let start = output.length
    appendBlocks(blocks, indent: indent + style.indentStep)
    decorate(from: start, with: decoration)
  }

  /// Marks everything emitted since `start` as one decorated block. **The only
  /// writer of `.rfcDecoration`.**
  ///
  /// Two rules have to hold for a block to draw as one band, and both were learned
  /// the hard way. The value is stored as its raw `String` because a boxed Swift
  /// enum does not reliably compare equal across insertions, and runs that do not
  /// compare equal do not merge. And *every* character between the block's first
  /// and last must carry it — a separator newline emitted without it splits the
  /// run, and the renderer then reads each half as a complete decoration and draws
  /// it as its own fully rounded card. Decorating a finished range, rather than
  /// asking each `append` to remember, is what makes both unconditional.
  func decorate(from start: Int, with decoration: RFCDecoration) {
    guard output.length > start else { return }
    let range = NSRange(location: start, length: output.length - start)
    // A nested quote or aside has already claimed its own span, and the inner,
    // more specific decoration is the one to keep — so fill only what it left unset.
    var gaps: [NSRange] = []
    output.enumerateAttribute(.rfcDecoration, in: range) { value, subrange, _ in
      if value == nil { gaps.append(subrange) }
    }
    for gap in gaps {
      output.addAttribute(.rfcDecoration, value: decoration.rawValue, range: gap)
    }
  }
}
