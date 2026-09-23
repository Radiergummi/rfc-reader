/// How much of a long list is handed to SwiftUI at once.
///
/// The library's `All RFCs` filter is 9,842 rows, and giving them to a `List` in one
/// update is a single large diff on the main thread: AppKit has to build the table's
/// whole identity set, and its type-ahead then scans every row to assemble the
/// strings it matches against -- long enough that it gives up and logs "Type
/// selection took over 1.000 seconds". Neither cost is paid for rows nobody has
/// scrolled to yet.
///
/// So the view renders a prefix and grows it as the end comes into sight. The
/// arithmetic is here rather than in the view because the App target has no test
/// bundle, and the cases that matter are the ones that are tedious to produce by
/// hand: a list shorter than one page, a window already at the end, a selection far
/// below the first page.
///
/// It also answers the reentrancy that issue #22 carried unexplained through a
/// breakpoint sweep of every public `NSTableView` and `NSOutlineView` mutation, none
/// of which ever fired:
///
///     WARNING: Application performed a reentrant operation in its NSTableView
///     delegate. This warning will become an assert in the future.
///
/// Measured as an A/B over six launches of the same debug build, differing only in
/// whether `RFCListView` windows -- three before, one warning each; three after,
/// none. So it was a consequence of the size of the table update rather than of
/// anything the app calls, which is why no breakpoint caught it. That is the launch
/// case only, where nothing has been clicked; it says nothing about whether the
/// selection bindings can still provoke one under interaction.
public enum ListWindow {
    /// Rows in the first page, and added by each extension.
    ///
    /// Comfortably more than fills the tallest window, so the first page never
    /// arrives visibly short and a fresh filter needs no extension to look complete.
    public static let page = 150

    /// How far from the end of the window a row has to appear before the next page
    /// is added. Enough runway that the extension is prepared while there is still
    /// something below to look at, rather than at the moment the list runs out.
    public static let lead = 50

    /// The window a list starts at.
    ///
    /// Widened to reach `selectedRow` when there is one, because a selection can
    /// arrive from outside the list -- a deep link, a citation, the Go to RFC
    /// palette -- and `NavigationModel.open` deliberately resets the filter to `.all`
    /// so the document it landed on cannot be hidden by a narrowed one. A window that
    /// stopped at the first page would hide it again, and `RFC 2119` sits around row
    /// 7,700 of the reversed index.
    public static func initialLimit(covering selectedRow: Int? = nil) -> Int {
        guard let selectedRow, selectedRow >= page else { return page }
        // The whole page the row falls in, so the selection is not left clinging to
        // the last row of the window with nothing after it.
        return (selectedRow / page + 1) * page
    }

    /// The row whose appearance adds the next page, or nil once the window already
    /// covers everything.
    ///
    /// One row rather than a test every row applies to itself: the view compares its
    /// own against this and does nothing otherwise, so the common case is an equality
    /// check and the arithmetic runs once per body pass rather than once per row.
    public static func triggerRow(limit: Int, total: Int) -> Int? {
        guard limit < total else { return nil }
        return limit - lead
    }

    /// The window one page further on, never past the end.
    public static func extendedLimit(from limit: Int, total: Int) -> Int {
        min(limit + page, total)
    }
}
