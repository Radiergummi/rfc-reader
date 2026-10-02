/// Packet diagrams hand-written in the shape of an RFC's, never quoted from one.
/// Lines 0 and 1 are the ruler, 2 to 6 the grid.
enum PacketSamples {
  private static let ruler = [
    "    0                   1",
    "    0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5",
  ]
  private static let border = "   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+"

  /// One field, its name across an open border that holds a hyphen.
  static let hyphenated =
    (ruler + [
      border,
      "   |             Long              |",
      "   +            Hyphen-            +",
      "   |             Name              |",
      border,
    ]).joined(separator: "\n")

  /// Two fixed fields over one of no fixed length.
  static let variable =
    (ruler + [
      border,
      "   |     Type      |    Length     |",
      border,
      "   ~             Value             ~",
      border,
    ]).joined(separator: "\n")

  /// A name spelled with a combining circumflex: one `Character`, two UTF-16 units.
  static let combining =
    (ruler + [
      border,
      "   |     Type      |    Le\u{0302}ngth     |",
      border,
    ]).joined(separator: "\n")

  /// A caption after a blank line, inside the same block.
  static let captioned = variable + "\n\n   Figure 1: A sample header"
}
