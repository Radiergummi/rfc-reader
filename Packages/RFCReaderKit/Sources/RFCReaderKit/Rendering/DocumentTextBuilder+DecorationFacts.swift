import Foundation

extension DocumentTextBuilder {
  /// Sets each decorated block's `DecorationFacts` on every character of it, so a
  /// fragment reads its block with one lookup (#766).
  ///
  /// The last pass of a build, once every decoration, indent, inset and width is
  /// in place: blocks nest and are decorated inside out, a verbatim block cuts its
  /// decoration's run, and the whole-point pass rewrites the paragraph styles the
  /// indent is read from.
  ///
  /// A run is boxed piece by piece along its verbatim blocks: each block gets its
  /// own facts, and what lies between them the run's, as `decorationSpan` read them
  /// when it walked. Each extent is walked once: the run is the one this
  /// enumeration names, and a verbatim block is the piece of it its box covers.
  func setDecorationFacts() {
    var boxed: [(range: NSRange, facts: DecorationFacts)] = []
    let whole = NSRange(location: 0, length: output.length)
    output.enumerateAttribute(.rfcDecoration, in: whole) { value, run, _ in
      guard value != nil else { return }
      var runFacts: DecorationFacts?
      output.enumerateAttribute(.rfcVerbatim, in: run) { box, piece, _ in
        if box is VerbatimBox {
          boxed.append((piece, FragmentGeometry.decorationFacts(in: output, block: piece)))
        } else {
          let facts = runFacts ?? FragmentGeometry.decorationFacts(in: output, block: run)
          runFacts = facts
          boxed.append((piece, facts))
        }
      }
    }
    for (range, facts) in boxed {
      output.addAttribute(.rfcDecorationFacts, value: facts, range: range)
    }
  }
}
