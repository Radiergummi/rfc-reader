#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  /// The context menu of a heading's backlink chip (#183), on macOS.
  @MainActor
  public enum BacklinkMenu {
    /// `NSTextView`'s menu for the chip, less its Copy Link item, matched by its
    /// `copyLink:` action: the chip's URL means nothing outside the reader. The rest
    /// stays, Copy and Copy as Quote for a selection among it. A copy, so the item
    /// is not left missing from a menu AppKit hands out again.
    public static func withoutCopyLink(_ menu: NSMenu) -> NSMenu {
      let result = (menu.copy() as? NSMenu) ?? NSMenu()
      for item in result.items where item.action == copyLink {
        result.removeItem(item)
      }
      return result
    }

    private static let copyLink = Selector(("copyLink:"))
  }
#endif
