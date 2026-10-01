import Foundation
import RFCKit

/// A packet diagram as decorated text: its borders drawn as lines, its field names
/// and ruler left as the text they are.
enum PacketPresentation {
  static let entry = RendererEntry(
    types: [ArtworkType.packet.name],
    presentations: [
      Presentation(id: "packet-grid") { block, _, _ in render(block.text) }
    ])

  static func render(_ text: String) -> Rendition? {
    guard let (diagram, layout) = PacketDiagram.analyze(text),
      !text.unicodeScalars.contains(where: isDoubleWidth)
    else { return nil }
    // Columns count `Character`s, the storage UTF-16 units; they part at the first
    // character outside the Basic Multilingual Plane or with a combining mark. So
    // each line is walked once, into the UTF-16 range of every column.
    var columns: [[NSRange]] = []
    var offset = 0
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
      var ranges: [NSRange] = []
      for character in line {
        let length = character.utf16.count
        ranges.append(NSRange(location: offset, length: length))
        offset += length
      }
      columns.append(ranges)
      offset += 1
    }
    func lineRange(_ line: Int) -> NSRange {
      guard let first = columns[line].first, let last = columns[line].last else {
        return NSRange(location: 0, length: 0)
      }
      return NSRange(location: first.location, length: NSMaxRange(last) - first.location)
    }
    return .decorated(
      DecoratedText(
        hidden: layout.marks.map { columns[$0.line][$0.column] },
        secondary: layout.rulerLines.map(lineRange),
        strokes: strokes(for: layout.marks),
        spokenLabel: PacketSummary.spoken(diagram)))
  }

  /// A character a monospaced font sets two cells wide: CJK ideographs and syllables,
  /// full-width forms and emoji. Counted as one column, it would put every line
  /// after it on its row a cell off the border it draws.
  static func isDoubleWidth(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
      0xA000...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60,
      0xFFE0...0xFFE6, 0x1F300...0x1F64F, 0x1F900...0x1F9FF, 0x20000...0x3FFFD:
      true
    default:
      false
    }
  }

  private struct Cell: Hashable {
    var line: Int
    var column: Int
  }

  /// Each mark as the lines through its cell: a rule across it, a delimiter down
  /// it, and a corner halfway toward every neighbor that draws toward it. Then the
  /// pieces that touch are joined, so a dashed edge runs unbroken and a fragment
  /// draws one line rather than one per cell.
  static func strokes(for marks: [PacketDiagram.Mark]) -> [Stroke] {
    var kinds: [Cell: PacketDiagram.MarkKind] = [:]
    for mark in marks {
      kinds[Cell(line: mark.line, column: mark.column)] = mark.kind
    }
    var pieces: [Stroke] = []
    // In either order: a stroke runs from its upper or left end.
    func add(_ one: (Int, Int), _ other: (Int, Int), _ style: Stroke.Style) {
      let (start, end) = one <= other ? (one, other) : (other, one)
      pieces.append(
        Stroke(
          start: GridPoint(x: start.0, y: start.1), end: GridPoint(x: end.0, y: end.1), style: style
        ))
    }
    for mark in marks {
      let x = 2 * mark.column + 1
      let y = 2 * mark.line + 1
      switch mark.kind {
      case .rule, .doubleRule:
        add((x - 1, y), (x + 1, y), style(of: mark.kind))
      case .delimiter, .variableDelimiter:
        add((x, y - 1), (x, y + 1), style(of: mark.kind))
      case .corner:
        for (across, down) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
          guard
            let neighbor = kinds[Cell(line: mark.line + down, column: mark.column + across)],
            across == 0 ? drawsDown(neighbor) : drawsAcross(neighbor)
          else { continue }
          add((x, y), (x + across, y + down), style(of: neighbor))
        }
      }
    }
    return joined(pieces)
  }

  private static func drawsAcross(_ kind: PacketDiagram.MarkKind) -> Bool {
    kind == .rule || kind == .doubleRule || kind == .corner
  }

  private static func drawsDown(_ kind: PacketDiagram.MarkKind) -> Bool {
    kind == .delimiter || kind == .variableDelimiter || kind == .corner
  }

  private static func style(of kind: PacketDiagram.MarkKind) -> Stroke.Style {
    switch kind {
    case .doubleRule: .double
    case .variableDelimiter: .dashed
    case .corner, .rule, .delimiter: .solid
    }
  }

  private struct Axis: Hashable {
    var horizontal: Bool
    var position: Int
    var style: Stroke.Style
  }

  /// Collinear pieces in the same style that touch or overlap, as one stroke each.
  static func joined(_ pieces: [Stroke]) -> [Stroke] {
    var spans: [Axis: [ClosedRange<Int>]] = [:]
    var order: [Axis] = []
    for piece in pieces {
      let horizontal = piece.start.y == piece.end.y
      let axis = Axis(
        horizontal: horizontal, position: horizontal ? piece.start.y : piece.start.x,
        style: piece.style)
      if spans[axis] == nil { order.append(axis) }
      spans[axis, default: []].append(
        horizontal ? piece.start.x...piece.end.x : piece.start.y...piece.end.y)
    }
    var result: [Stroke] = []
    for axis in order {
      let sorted = (spans[axis] ?? []).sorted { $0.lowerBound < $1.lowerBound }
      guard var current = sorted.first else { continue }
      for span in sorted.dropFirst() {
        if span.lowerBound <= current.upperBound {
          current = current.lowerBound...max(current.upperBound, span.upperBound)
        } else {
          result.append(stroke(along: axis, current))
          current = span
        }
      }
      result.append(stroke(along: axis, current))
    }
    return result
  }

  private static func stroke(along axis: Axis, _ span: ClosedRange<Int>) -> Stroke {
    axis.horizontal
      ? Stroke(
        start: GridPoint(x: span.lowerBound, y: axis.position),
        end: GridPoint(x: span.upperBound, y: axis.position), style: axis.style)
      : Stroke(
        start: GridPoint(x: axis.position, y: span.lowerBound),
        end: GridPoint(x: axis.position, y: span.upperBound), style: axis.style)
  }
}
