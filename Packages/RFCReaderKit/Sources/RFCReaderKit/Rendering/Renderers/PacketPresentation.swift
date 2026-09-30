import Foundation
import RFCKit

/// A packet diagram as decorated text: its borders drawn as lines, its field names
/// and ruler left as the text they are.
enum PacketPresentation {
  static let entry = RendererEntry(
    types: ["packet"],
    presentations: [
      Presentation(id: "packet-grid") { block, _, _ in render(block.text) }
    ])

  static func render(_ text: String) -> Rendition? {
    guard let layout = PacketDiagram.layout(of: text) else { return nil }
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var lineStarts: [Int] = []
    var offset = 0
    for line in lines {
      lineStarts.append(offset)
      offset += line.utf16.count + 1
    }
    // Columns count `Character`s, the storage UTF-16 units; they part at the first
    // character outside the Basic Multilingual Plane or with a combining mark.
    func range(of mark: PacketDiagram.Mark) -> NSRange {
      let line = lines[mark.line]
      let start = line.index(line.startIndex, offsetBy: mark.column)
      return NSRange(
        location: lineStarts[mark.line] + line[..<start].utf16.count,
        length: line[start].utf16.count)
    }
    return .decorated(
      DecoratedText(
        hidden: layout.marks.map(range(of:)),
        secondary: layout.rulerLines.map {
          NSRange(location: lineStarts[$0], length: lines[$0].utf16.count)
        },
        strokes: strokes(for: layout.marks)))
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
    func add(_ start: (Int, Int), _ end: (Int, Int), _ style: Stroke.Style) {
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
        if let left = kinds[Cell(line: mark.line, column: mark.column - 1)], drawsAcross(left) {
          add((x - 1, y), (x, y), style(of: left))
        }
        if let right = kinds[Cell(line: mark.line, column: mark.column + 1)], drawsAcross(right) {
          add((x, y), (x + 1, y), style(of: right))
        }
        if let above = kinds[Cell(line: mark.line - 1, column: mark.column)], drawsDown(above) {
          add((x, y - 1), (x, y), style(of: above))
        }
        if let below = kinds[Cell(line: mark.line + 1, column: mark.column)], drawsDown(below) {
          add((x, y), (x, y + 1), style(of: below))
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
