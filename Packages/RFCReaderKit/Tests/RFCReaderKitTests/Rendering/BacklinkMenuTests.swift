#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit
  import Testing

  @testable import RFCReaderKit

  /// A right-click on a heading's backlink caption (#183) keeps the text view's menu,
  /// less Copy Link: the caption's URL means nothing outside the reader.
  @Suite("Backlink caption menu")
  @MainActor
  struct BacklinkMenuTests {
    @Test func `the caption's menu keeps everything but Copy Link`() {
      let menu = NSMenu()
      menu.addItem(withTitle: "Open Link", action: Selector(("openLink:")), keyEquivalent: "")
      menu.addItem(withTitle: "Copy Link", action: Selector(("copyLink:")), keyEquivalent: "")
      menu.addItem(.separator())
      menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
      menu.addItem(
        withTitle: "Copy as Quote", action: Selector(("copyAsQuote:")), keyEquivalent: "")

      let captionMenu = BacklinkMenu.withoutCopyLink(menu)

      #expect(captionMenu.items.map(\.title) == ["Open Link", "", "Copy", "Copy as Quote"])
      #expect(menu.items.count == 5, "AppKit may hand the same menu out again")
    }
  }
#endif
