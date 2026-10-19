import CoreGraphics
import Foundation

// The gutter markers of notes (#523): a glyph in the trailing gutter, level with the
// first line of what each note is on. The leading gutter is kept for hung section
// numbers (#433). Slice 3's notes column places its cards by the same lines.

extension FragmentGeometry {
  /// Where one note's target starts, as layout has it: the top of that line, in the
  /// text container's coordinates, and whether its fragment is laid out or its frame
  /// only an estimate.
  public struct NoteLine: Equatable, Sendable {
    public let note: UUID
    public let y: CGFloat
    public let height: CGFloat
    public let isLaidOut: Bool

    public init(note: UUID, y: CGFloat, height: CGFloat, isLaidOut: Bool) {
      self.note = note
      self.y = y
      self.height = height
      self.isLaidOut = isLaidOut
    }
  }

  /// One marker: the notes it opens, one, or several that share a line, its top,
  /// and the height of the line it stands by.
  public struct NoteMarker: Equatable, Sendable {
    public let notes: [UUID]
    public let y: CGFloat
    public let lineHeight: CGFloat

    public init(notes: [UUID], y: CGFloat, lineHeight: CGFloat) {
      self.notes = notes
      self.y = y
      self.lineHeight = lineHeight
    }
  }

  /// A marker's side, square.
  public static let noteMarkerSize: CGFloat = 18
  /// The least space between two stacked markers.
  public static let noteMarkerSpacing: CGFloat = 2
  /// How far past what is visible markers are placed, so that a scroll brings in a
  /// marker already there.
  public static let noteMarkerMargin: CGFloat = 400

  /// The markers for `lines`, in the order of the document. Only over real layout,
  /// and only inside `visible`: a line laid out on an estimate, or outside, has none,
  /// so a marker never shows where its line is not. The notes of one line share a
  /// marker; a marker that would overlap the one above it moves down beneath it.
  public static func noteMarkers(_ lines: [NoteLine], visible: ClosedRange<CGFloat>)
    -> [NoteMarker]
  {
    // The lines, one marker each, the notes of one line together.
    var grouped: [NoteMarker] = []
    let real = lines.filter { $0.isLaidOut && visible.contains($0.y) }
    for line in real.sorted(by: { $0.y < $1.y }) {
      if let last = grouped.last, abs(last.y - line.y) < 1 {
        grouped[grouped.count - 1] = NoteMarker(
          notes: last.notes + [line.note], y: last.y, lineHeight: last.lineHeight)
      } else {
        grouped.append(NoteMarker(notes: [line.note], y: line.y, lineHeight: line.height))
      }
    }
    var markers: [NoteMarker] = []
    for group in grouped {
      let below = markers.last.map { $0.y + noteMarkerSize + noteMarkerSpacing } ?? -.infinity
      markers.append(
        NoteMarker(notes: group.notes, y: max(group.y, below), lineHeight: group.lineHeight))
    }
    return markers
  }

  /// A marker's frame in the text view: in the trailing gutter, just past the
  /// column, centered on its line's height; inside the view where the gutter is
  /// narrower than a marker, as on a phone.
  public static func noteMarkerFrame(
    _ marker: NoteMarker, containerOrigin: CGPoint, columnWidth: CGFloat, viewWidth: CGFloat
  ) -> CGRect {
    let size = noteMarkerSize
    let x = min(containerOrigin.x + columnWidth + 4, viewWidth - size)
    let y = containerOrigin.y + marker.y + max(0, (marker.lineHeight - size) / 2)
    return CGRect(x: x, y: y, width: size, height: size)
  }
}
