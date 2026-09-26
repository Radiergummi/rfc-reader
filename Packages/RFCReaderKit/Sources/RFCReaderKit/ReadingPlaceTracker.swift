import CoreGraphics
import Foundation

/// When the line at the top of the viewport is the reader's place, and when it is
/// not.
///
/// Tracking is only as good as the layout it samples. A change of column re-wraps
/// the storage under an unmoved scroll offset long before its rebuild lands, and
/// TextKit lays the viewport out again from estimates: measured on RFC 9000, the top
/// then showed text 45,000 characters from the reader's line, and recording it is
/// what the rebuild duly restored (#30). So tracking pauses on the change of column
/// itself and resumes only once the storage is laid out at the column again and the
/// place is back at the top. Keyed on the container's width instead, it resumed the
/// moment a column came back — wide, narrow, wide inside the rebuild's debounce —
/// on a layout TextKit had already thrown away.
public struct ReadingPlaceTracker: Sendable, Equatable {
    public enum Place: Sendable, Equatable {
        /// Scrolled above the text, where the header is. Restored to the very top
        /// rather than to the first character, which would hide the header.
        case top
        case line(ReadingPlace)
    }

    public private(set) var place: Place?
    private var hasStorage = false
    /// The column the storage is laid out at, or nil while it is not laid out at
    /// any: nothing is installed, or it went in before the first column was known.
    private var storageColumn: CGFloat?
    private var isTracking = false
    /// Where the last restore left the viewport's top. A restore at the document's
    /// end is clamped, so the line at the top there is not the one holding the
    /// place; until the reader scrolls away from it, the place is the one carried.
    private var restoredTop: CGFloat?

    public init() {}

    /// A new storage went in, laid out at `column` — nil if no column is known yet.
    /// Tracking waits for `restored(top:)`.
    public mutating func installed(atColumn column: CGFloat?) {
        hasStorage = true
        storageColumn = column
        isTracking = false
        restoredTop = nil
    }

    /// The text container is now `column` wide. True if the storage can be laid out
    /// at it right away — it is the column the storage was laid out at before, or
    /// the first column a storage installed ahead of any gets — in which case the
    /// caller lays it out, restores the place and calls `restored(top:)`. False
    /// means the storage belongs to another column, and tracking waits for the
    /// rebuild's `installed(atColumn:)`.
    ///
    /// A storage installed before any column is taken to be built at the first one,
    /// which holds only while the reader and the view that builds it derive the
    /// column from the same width.
    public mutating func columnChanged(to column: CGFloat) -> Bool {
        isTracking = false
        restoredTop = nil
        guard hasStorage else { return false }
        if storageColumn == nil { storageColumn = column }
        return storageColumn == column
    }

    /// The storage is laid out and the place, if there was one, is back at the top
    /// of the viewport, which is now at `top` — nil if nothing was restored.
    public mutating func restored(top: CGFloat?) {
        isTracking = true
        restoredTop = top
    }

    /// A jump names the place directly, and holds even while tracking waits: a jump
    /// between a change of column and its rebuild is where the rebuild must land.
    public mutating func jumped(to place: ReadingPlace) {
        self.place = .line(place)
        restoredTop = nil
    }

    /// The viewport's top is at `viewportTop`, in container coordinates, and `line`
    /// is the line there.
    public mutating func report(viewportTop: CGFloat, line: NSRange, in index: AnchorIndex, length: Int) {
        guard isTracking, viewportTop != restoredTop else { return }
        restoredTop = nil
        guard viewportTop >= 0 else {
            place = .top
            return
        }
        let previous: ReadingPlace? = if case .line(let previous) = place { previous } else { nil }
        place = .line(ReadingPlace.tracking(previous, topLine: line, in: index, length: length))
    }
}
