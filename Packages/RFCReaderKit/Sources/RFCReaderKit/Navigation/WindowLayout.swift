import Foundation

/// What a Mac window's split view looked like, for the window to come back so
/// (#762): whether the panel was open and on which pane, and how wide the columns
/// were. Kept in the window's `SceneSnapshot` rather than by an `NSSplitView`
/// autosave name, which would put widths back before the window's minimum width and
/// the panel's rule have had their say.
public struct WindowLayout: Codable, Equatable, Sendable {
  public var panelIsOpen: Bool
  public var pane: InspectorPane
  /// The width of each column the reader can drag, nil for one that was collapsed:
  /// a collapsed column's width is not one to give back. The panel's is fixed
  /// (`ReaderLayout.panelWidth`).
  public var sidebarWidth: Double?
  public var listWidth: Double?

  public init(
    panelIsOpen: Bool, pane: InspectorPane, sidebarWidth: Double? = nil, listWidth: Double? = nil
  ) {
    self.panelIsOpen = panelIsOpen
    self.pane = pane
    self.sidebarWidth = sidebarWidth
    self.listWidth = listWidth
  }
}
