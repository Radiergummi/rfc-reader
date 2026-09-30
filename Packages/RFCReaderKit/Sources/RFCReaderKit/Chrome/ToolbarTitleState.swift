import CoreGraphics

/// Everything the reader tells its toolbar title as it scrolls: how far the title
/// has come in (`ToolbarTitleReveal`), and what its subtitle says (`RunningHeading`).
public struct ToolbarTitleState: Equatable, Sendable {
  public let reveal: CGFloat
  public let runningHeading: RunningHeading.State

  public init(reveal: CGFloat, runningHeading: RunningHeading.State) {
    self.reveal = reveal
    self.runningHeading = runningHeading
  }

  /// The title in full, over the document's own title: where there is no header
  /// on screen to show them instead.
  public static let shown = ToolbarTitleState(reveal: 1, runningHeading: .steady(nil))

  /// Nothing in the toolbar, because the header is showing it.
  public static let hidden = ToolbarTitleState(reveal: 0, runningHeading: .steady(nil))
}
