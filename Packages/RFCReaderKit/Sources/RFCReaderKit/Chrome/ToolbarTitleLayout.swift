import CoreGraphics

/// How wide the window's own title is drawn, given the column it sits over.
///
/// The title is a toolbar item rather than AppKit's, so its width is ours to work
/// out — and it is a pure function of the text's width and the column's, which is
/// why it is here and not in the view that applies it.
public enum ToolbarTitleLayout {
  /// The leading padding the title is inset by, and as much again at the trailing
  /// edge so it stops short of the divider rather than against it.
  public static let padding: CGFloat = 8

  /// Narrow enough to be worth drawing at all: below this the title is only an
  /// ellipsis, and the sidebar shows which collection is chosen anyway.
  static let minimumWidth: CGFloat = 80

  public static func width(forText text: CGFloat, inColumn column: CGFloat) -> CGFloat {
    min(text + padding * 2, max(minimumWidth, column - padding * 3))
  }

  /// Whether a title squeezed to this width still says anything. The reader's
  /// title flexes with the room between Back/Forward and the document's actions,
  /// and below this it draws nothing rather than a lone ellipsis.
  public static func isWorthDrawing(width: CGFloat) -> Bool {
    width >= minimumWidth
  }
}
