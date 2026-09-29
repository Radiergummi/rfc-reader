import Foundation

/// A packet-format diagram, the corpus's most common figure, as the fields it draws
/// (#47): each field's name, the row it starts on, its bit offset and width, and
/// how many rows it spans.
///
///      0                   1
///      0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5
///     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
///     |      Type     |     Length    |
///     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
///
/// Recognized exactly or not at all. The bit ruler is required, because it is what
/// fixes the column of every bit: bit `i` is set at `x₀ + 2i`, under its digit, and
/// the boundary before it at `x₀ + 2i − 1`. Every other line has to be a border or a
/// row of fields whose delimiters fall on those boundaries, and a block with
/// anything else in it is not a packet diagram. A blank line ends the diagram,
/// because the parser keeps a caption with the artwork above it; what follows is
/// not read.
///
/// Recognized on demand from an artwork block's text, which stays the source of
/// truth: RFCXML has nowhere to write a parsed layout, so the model carries none.
public struct PacketDiagram: Equatable, Sendable {
  public struct Field: Equatable, Sendable {
    /// The text drawn inside the field, its lines joined with spaces. A name spelled
    /// one letter a line, as a one-bit field's is, reads down: `URG`.
    public var name: String
    /// The row the field starts on, counted from zero.
    public var row: Int
    /// The bit the field starts at, within its first row.
    public var bitOffset: Int
    /// How many bits the field is drawn over, across all its rows.
    public var bitWidth: Int
    public var rowSpan: Int
    /// Drawn between `~`, `:`, `/`, `\\` or `.` rather than `|`: its length is not
    /// the width drawn.
    public var isVariableLength: Bool

    public init(
      name: String, row: Int, bitOffset: Int, bitWidth: Int, rowSpan: Int = 1,
      isVariableLength: Bool = false
    ) {
      self.name = name
      self.row = row
      self.bitOffset = bitOffset
      self.bitWidth = bitWidth
      self.rowSpan = rowSpan
      self.isVariableLength = isVariableLength
    }
  }

  /// The ruler's width: 32 for most, 8, 16 or 64 for some.
  public var bitsPerRow: Int
  /// In the order they are drawn: by row, then by offset.
  public var fields: [Field]

  public init(bitsPerRow: Int, fields: [Field]) {
    self.bitsPerRow = bitsPerRow
    self.fields = fields
  }

  /// The diagram `text` draws, or nil when it is not exactly a packet diagram.
  public static func recognize(_ text: String) -> PacketDiagram? {
    var recognizer = Recognizer(text: text)
    return recognizer.run()
  }
}

/// The work of `PacketDiagram.recognize`, over lines as arrays of characters so a
/// column is an index.
private struct Recognizer {
  let lines: [[Character]]

  init(text: String) {
    lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
      Array(line.reversed().drop(while: \.isWhitespace).reversed())
    }
  }

  /// The ruler's first bit column, and its width.
  private var origin = 0
  private var bits = 0

  private func boundary(_ bit: Int) -> Int { origin - 1 + 2 * bit }
  private func cell(_ bit: Int) -> Int { origin + 2 * bit }

  private static func character(_ line: [Character], _ column: Int) -> Character {
    column >= 0 && column < line.count ? line[column] : " "
  }

  // MARK: - Ruler

  private static let digits = Array("0123456789")

  /// The bits' line, `0 1 2 … 9 0 1`: a digit every two columns, each the bit's
  /// number modulo ten, and nothing else.
  private static func units(_ line: [Character]) -> (origin: Int, bits: Int)? {
    guard let origin = line.firstIndex(where: { !$0.isWhitespace }) else { return nil }
    var bits = 0
    var column = origin
    while column < line.count {
      guard line[column] == Self.digits[bits % 10] else { return nil }
      bits += 1
      if column + 1 < line.count, line[column + 1] != " " { return nil }
      column += 2
    }
    guard bits >= 8, bits <= 64, bits % 8 == 0 else { return nil }
    return (origin, bits)
  }

  /// The tens line above it: the tens digit over every tenth bit,
  /// `0                   1`, the same without the zero, or over every bit from
  /// ten on, `1 1 1 1 1 1`, and nothing else.
  private func isTens(_ line: [Character]) -> Bool {
    let digits = line.enumerated().filter { $0.element != " " }
    let bitsUnder = digits.map { column, character -> Int? in
      let offset = column - origin
      guard offset >= 0, offset % 2 == 0, offset / 2 < bits,
        character == Self.digits[offset / 20 % 10]
      else { return nil }
      return offset / 2
    }
    guard !bitsUnder.contains(nil) else { return false }
    let numbered = bitsUnder.compactMap { $0 }
    let everyTenth = Array(stride(from: 0, to: bits, by: 10))
    return numbered == everyTenth || numbered == Array(everyTenth.dropFirst())
      || numbered == Array(10..<bits)
  }

  // MARK: - Grid

  private enum Line {
    case border([Character])
    case content([Character])
  }

  /// The segments of a row of fields: each field's first bit and the bit after its
  /// last.
  private struct Row {
    var lines: [[Character]]
    var end: Int
    var segments: [Range<Int>]
    /// The segments drawn against a variable-length mark: the first, when a line
    /// starts with one, and the last, when a line ends with one.
    var variableSegments: Set<Int>
  }

  mutating func run() -> PacketDiagram? {
    guard let rulerIndex = lines.firstIndex(where: { !$0.isEmpty }),
      let ruler = findRuler(from: rulerIndex), ruler < lines.count
    else { return nil }
    // A grid at the margin has no column for the boundary left of bit 0, and puts
    // its corners under the digits instead: the same grid, one column right.
    if lines[ruler].firstIndex(where: { !$0.isWhitespace }) == origin {
      origin += 1
    }
    guard origin >= 1 else { return nil }
    var grid: [Line] = []
    for line in lines[ruler...] {
      if line.isEmpty { break }
      guard let classified = classify(line) else { return nil }
      grid.append(classified)
    }
    guard case .border = grid.first, case .border = grid.last else { return nil }

    var borders: [[Character]] = []
    var rows: [Row] = []
    var pending: [[Character]] = []
    for line in grid {
      switch line {
      case .content(let characters):
        pending.append(characters)
      case .border(let characters):
        if !borders.isEmpty {
          guard !pending.isEmpty, let row = row(of: pending) else { return nil }
          rows.append(row)
        }
        pending = []
        borders.append(characters)
      }
    }
    guard !rows.isEmpty else { return nil }
    return fields(rows: rows, borders: borders)
  }

  /// The index of the first grid line, once the ruler above it is read.
  private mutating func findRuler(from first: Int) -> Int? {
    if let (origin, bits) = Self.units(lines[first]) {
      // Without a tens line only when there is no second ten to number.
      guard bits <= 10 else { return nil }
      (self.origin, self.bits) = (origin, bits)
      return first + 1
    }
    guard first + 1 < lines.count, let (origin, bits) = Self.units(lines[first + 1]) else {
      return nil
    }
    (self.origin, self.bits) = (origin, bits)
    return isTens(lines[first]) ? first + 2 : nil
  }

  /// What stands in a field's delimiter's place at the ends of a row, for a field
  /// of no fixed length.
  private static let variableMarks: Set<Character> = ["~", ":", "/", "\\", "."]

  /// A border starts with `+`, a row of fields with `|` or a variable-length mark,
  /// both at the first boundary with nothing before it, and both end on a boundary.
  private func classify(_ line: [Character]) -> Line? {
    guard line.count > boundary(0), line[..<boundary(0)].allSatisfy({ $0 == " " }),
      let end = endBit(of: line)
    else { return nil }
    switch line[boundary(0)] {
    case "+":
      guard line[boundary(end)] == "+" else { return nil }
      // A `+` is a corner, and a corner is on a boundary.
      for (column, character) in line.enumerated() where character == "+" {
        guard (column - boundary(0)) % 2 == 0 else { return nil }
      }
      return .border(line)
    case let first where first == "|" || Self.variableMarks.contains(first):
      let last = line[boundary(end)]
      guard last == "|" || Self.variableMarks.contains(last) else { return nil }
      for (column, character) in line.enumerated() where character == "|" {
        guard (column - boundary(0)) % 2 == 0 else { return nil }
      }
      return .content(line)
    default:
      return nil
    }
  }

  /// The bit whose boundary the line's last character is on.
  private func endBit(of line: [Character]) -> Int? {
    let last = line.count - 1 - boundary(0)
    guard last > 0, last % 2 == 0, last / 2 <= bits else { return nil }
    return last / 2
  }

  /// The fields of one row, from the lines between two borders. Every line has to
  /// end on the same boundary and put a delimiter on the same boundaries.
  private func row(of lines: [[Character]]) -> Row? {
    let ends = Set(lines.compactMap(endBit(of:)))
    guard ends.count == 1, let end = ends.first else { return nil }
    var starts = [0]
    for bit in 1..<end {
      // A tilde standing alone there would end a field of no fixed length, which
      // only a row's ends can mark.
      let tilde = lines.contains { line in
        Self.character(line, boundary(bit)) == "~" && Self.character(line, boundary(bit) - 1) == " "
          && Self.character(line, boundary(bit) + 1) == " "
      }
      guard !tilde else { return nil }
      let delimited = lines.map { Self.character($0, boundary(bit)) == "|" }
      if delimited.allSatisfy({ $0 }) {
        starts.append(bit)
      } else if delimited.contains(true) {
        return nil
      }
    }
    let segments = zip(starts, starts.dropFirst() + [end]).map { $0..<$1 }
    var variableSegments = Set<Int>()
    if lines.contains(where: { $0[boundary(0)] != "|" }) { variableSegments.insert(0) }
    if lines.contains(where: { $0[boundary(end)] != "|" }) {
      variableSegments.insert(segments.count - 1)
    }
    return Row(lines: lines, end: end, segments: segments, variableSegments: variableSegments)
  }

  // MARK: - Fields

  /// What a rule is drawn with: `-`, or `=` for a double rule.
  private static let rules: Set<Character> = ["-", "="]

  /// Whether a border is open over `bit`: no rule drawn there, so the field above
  /// continues below. A rule's `-` or `=` runs into another like it or a corner; one
  /// between letters is part of a name written across the border, as a hyphen.
  private func isOpen(_ border: [Character], _ bit: Int) -> Bool {
    let character = Self.character(border, cell(bit))
    guard Self.rules.contains(character) else { return true }
    let beside = [cell(bit) - 1, cell(bit) + 1].map { Self.character(border, $0) }
    return !beside.contains { $0 == character || $0 == "+" }
  }

  private func fields(rows: [Row], borders: [[Character]]) -> PacketDiagram? {
    // Every border ends where the longer of its rows does, and the first and the
    // last are closed over the whole of their row.
    for (index, border) in borders.enumerated() {
      let above = index > 0 ? rows[index - 1].end : 0
      let below = index < rows.count ? rows[index].end : 0
      guard endBit(of: border) == max(above, below) else { return nil }
      let overlap = index == 0 || index == rows.count ? 0 : min(above, below)
      guard !(overlap..<max(above, below)).contains(where: { isOpen(border, $0) }) else {
        return nil
      }
    }

    // Segment `(row, index)` is joined with the one under it wherever the border
    // between them is open, and only there.
    struct Key: Hashable {
      var row: Int
      var index: Int
    }
    var parent = [Key: Key]()
    func find(_ node: Key) -> Key {
      var node = node
      while let next = parent[node], next != node { node = next }
      return node
    }
    func segmentIndex(_ row: Int, _ bit: Int) -> Int? {
      rows[row].segments.firstIndex { $0.contains(bit) }
    }
    for row in rows.indices.dropLast() {
      let border = borders[row + 1]
      for bit in 0..<min(rows[row].end, rows[row + 1].end) where isOpen(border, bit) {
        guard let upper = segmentIndex(row, bit), let lower = segmentIndex(row + 1, bit) else {
          return nil
        }
        parent[find(Key(row: row + 1, index: lower))] = find(Key(row: row, index: upper))
      }
    }
    // A border has to agree with itself: open wherever the two segments it lies
    // between are one field, closed wherever they are two.
    for row in rows.indices.dropLast() {
      let border = borders[row + 1]
      for bit in 0..<min(rows[row].end, rows[row + 1].end) {
        guard let upper = segmentIndex(row, bit), let lower = segmentIndex(row + 1, bit) else {
          return nil
        }
        let joined = find(Key(row: row, index: upper)) == find(Key(row: row + 1, index: lower))
        guard joined == isOpen(border, bit) else { return nil }
      }
    }

    /// One row's segment of a field.
    struct Part {
      var row: Int
      var index: Int
      var segment: Range<Int>
    }
    var groups: [Key: [Part]] = [:]
    var order: [Key] = []
    for (row, content) in rows.enumerated() {
      for (index, segment) in content.segments.enumerated() {
        let root = find(Key(row: row, index: index))
        if groups[root] == nil { order.append(root) }
        groups[root, default: []].append(Part(row: row, index: index, segment: segment))
      }
    }
    // A field is contiguous bits: it runs to the end of every row but its last, and
    // from the start of every row but its first. So it has one segment a row, and
    // two in one row, joined through the rows around them, are refused with the
    // rest.
    for parts in groups.values {
      guard parts.dropLast().allSatisfy({ $0.segment.upperBound == bits }),
        parts.dropFirst().allSatisfy({ $0.segment.lowerBound == 0 })
      else { return nil }
    }
    var fields: [PacketDiagram.Field] = []
    for root in order {
      let parts = groups[root]!
      let first = parts[0]
      var fragments: [String] = []
      for part in parts {
        let (row, segment) = (part.row, part.segment)
        for line in rows[row].lines {
          fragments.append(text(of: line, over: segment))
        }
        // The border under a row the field continues past can carry its name, over
        // the part of it the field continues under and no more: beside that is the
        // rule over the fields next to it.
        if let next = parts.first(where: { $0.row == row + 1 }) {
          let open =
            max(
              segment.lowerBound, next.segment.lowerBound)..<min(
              segment.upperBound, next.segment.upperBound)
          // A corner is where a delimiter meets the border, and inside the part the
          // field continues under, none does.
          let corner = open.dropFirst().contains {
            Self.character(borders[row + 1], boundary($0)) == "+"
          }
          guard !corner else { return nil }
          fragments.append(text(of: borders[row + 1], over: open))
        }
      }
      fields.append(
        PacketDiagram.Field(
          name: Self.name(from: fragments), row: first.row, bitOffset: first.segment.lowerBound,
          bitWidth: parts.map(\.segment.count).reduce(0, +), rowSpan: parts.count,
          isVariableLength: parts.contains { rows[$0.row].variableSegments.contains($0.index) }))
    }
    return PacketDiagram(bitsPerRow: bits, fields: fields)
  }

  /// What a line holds between a segment's delimiters, trimmed.
  private func text(of line: [Character], over segment: Range<Int>) -> String {
    let columns = (boundary(segment.lowerBound) + 1)..<boundary(segment.upperBound)
    let text = String(columns.map { Self.character(line, $0) })
    return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  /// A field's lines, joined with spaces, or read down when every line holds one
  /// letter.
  private static func name(from fragments: [String]) -> String {
    let words = fragments.filter { !$0.isEmpty }
    return words.joined(separator: words.allSatisfy { $0.count == 1 } ? "" : " ")
  }
}
