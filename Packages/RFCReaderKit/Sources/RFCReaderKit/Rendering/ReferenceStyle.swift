/// How a cross reference's label is set.
public enum ReferenceStyle: Sendable, Equatable {
  /// Tinted, behind its `doc.text` symbol (`.rfcChip`): the reader's.
  case chip
  /// Ordinary text a little heavier than the text around it, in its color, with
  /// no symbol: a print's.
  case plainText
  /// The label alone, looking like every other link the style sets: an exported
  /// PDF's, whose links are underlined and colored (`ReadingStyle.underlinesLinks`).
  case link
}
