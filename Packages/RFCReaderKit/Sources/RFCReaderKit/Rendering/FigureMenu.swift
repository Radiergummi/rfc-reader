import Foundation

/// The item in a rendered block's menu that switches it between its figure and its
/// text: the Mac's context menu, and on iOS the long-press menu under the figure's
/// lifted preview. The App target puts the item in its menu; its words are here.
public enum FigureMenu {
  /// The item's title when `shown` is showing: it offers the other.
  public static func title(
    offeredFrom shown: PresentationChoices.Presentation, locale: Locale = .interface
  ) -> String {
    switch shown {
    case .figure: String(kit: "Show as Text", locale: locale)
    case .text: String(kit: "Show as Figure", locale: locale)
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

  /// The whole of the item a long press at `location` is for, or nil where there
  /// is none. Not the item UIKit hands over, whose range is the storage run under
  /// the finger: a drawn diagram's colors cut its body into runs a line or less
  /// long.
  public static func itemRange(at location: Int, in text: NSAttributedString) -> NSRange? {
    text.extent(ofBox: .rfcFigureItem, at: location)
  }

  /// The whole of `box`'s item, found from `range`, which touches it: a selection
  /// Copy Figure copies the block of (`FigureCopy.box(in:of:)`), which may begin
  /// anywhere before it. An empty range is a location.
  public static func itemRange(
    of box: VerbatimBox, touching range: NSRange, in text: NSAttributedString
  ) -> NSRange? {
    let searched = NSIntersectionRange(
      NSRange(location: range.location, length: max(range.length, 1)),
      NSRange(location: 0, length: text.length))
    var location: Int?
    text.enumerateAttribute(.rfcVerbatim, in: searched) { value, run, stop in
      guard (value as? VerbatimBox) === box else { return }
      location = run.location
      stop.pointee = true
    }
    return location.flatMap { itemRange(at: $0, in: text) }
  }
}
