/// A column of the Mac's window, the sidebar or the list, that is collapsed while two
/// documents are compared (#187), so that the two readers have the window, and how it
/// is left when the comparison ends.
public struct ColumnSetAside: Sendable, Equatable {
  /// Whether the column was collapsed before the comparison collapsed it.
  public let wasCollapsed: Bool

  public init(wasCollapsed: Bool) {
    self.wasCollapsed = wasCollapsed
  }

  /// Whether the column is collapsed once the comparison ends, given whether it is
  /// now: as it was before, unless the reader opened it while comparing, which it
  /// then stays.
  public func isCollapsedAfterComparing(isCollapsedNow: Bool) -> Bool {
    isCollapsedNow && wasCollapsed
  }
}
