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
  /// when it walked.
  func setDecorationFacts() {
    var pieces: [NSRange] = []
    let whole = NSRange(location: 0, length: output.length)
    output.enumerateAttribute(.rfcDecoration, in: whole) { value, run, _ in
      guard value != nil else { return }
      output.enumerateAttribute(.rfcVerbatim, in: run) { _, piece, _ in pieces.append(piece) }
    }
    for piece in pieces {
      guard let facts = FragmentGeometry.decorationFacts(in: output, at: piece.location) else {
        continue
      }
      output.addAttribute(.rfcDecorationFacts, value: facts, range: piece)
    }
  }
}
