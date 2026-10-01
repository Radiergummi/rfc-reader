import Foundation

/// The item in a rendered block's menu that switches it between its figure and its
/// text: the Mac's context menu, and on iOS the long-press menu under the figure's
/// lifted preview. The App target puts the item in its menu; its words are here.
public enum FigureMenu {
  /// The item's title when `shown` is showing: it offers the other.
  public static func title(offeredFrom shown: PresentationChoices.Presentation) -> String {
    switch shown {
    case .figure: "Show as Text"
    case .text: "Show as Figure"
    }
  }

  /// The item's SF Symbol when `shown` is showing: of what it switches to.
  public static func symbol(offeredFrom shown: PresentationChoices.Presentation) -> String {
    switch shown {
    case .figure: "doc.plaintext"
    case .text: "square.grid.3x3"
    }
  }

  /// The other presentation: what the item switches to.
  public static func offered(from shown: PresentationChoices.Presentation)
    -> PresentationChoices.Presentation
  {
    switch shown {
    case .figure: .text
    case .text: .figure
    }
  }

  /// The tag of a block's long-press item (`rfcFigureItem`): one per block, so two
  /// blocks set one after the other are two items.
  public static func itemTag(of box: VerbatimBox) -> String {
    "figure-\(box.ordinal)"
  }
}
