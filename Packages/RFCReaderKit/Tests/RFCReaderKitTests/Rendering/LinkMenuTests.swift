#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit
  import RFCKit
  import Testing

  @testable import RFCReaderKit

  /// A right-click on a link in the reader, on macOS (#776): Copy Link hands out the
  /// public URL, never the reader's own, and a link to a document offers a tab.
  @Suite("Link menu")
  @MainActor
  struct LinkMenuTests {
    private let current = DocumentID.rfc(9110)
    private let index = RFCIndex(
      rfcs: [
        RFCMetadata(
          id: .rfc(7932), title: "Brotli Compressed Data Format",
          date: PublicationDate(year: 2016))
      ],
      series: [])
    private let bibliography = [
      ReferenceGroup(
        title: "Normative References",
        entries: [
          Reference(
            anchor: "ISO.8601", title: "Date and time format",
            url: URL(string: "https://www.iso.org/iso-8601-date-and-time-format.html")),
          Reference(anchor: "Unlinked", title: "A Paper"),
        ])
    ]

    private func items(_ string: String) -> LinkMenu.Items {
      LinkMenu.items(
        for: URL(string: string)!, from: current, in: index, bibliography: bibliography)
    }

    /// NSTextView's link menu, as far as these tests need it.
    private func textViewMenu() -> NSMenu {
      let menu = NSMenu()
      menu.addItem(withTitle: "Open Link", action: Selector(("openLink:")), keyEquivalent: "")
      menu.addItem(withTitle: "Copy Link", action: Selector(("copyLink:")), keyEquivalent: "")
      menu.addItem(.separator())
      menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
      return menu
    }

    @Test func `another RFC copies its public URL and opens in a tab`() {
      let items = items("rfc://7932#section-4.2")
      #expect(
        items.copyLink
          == .publicLink(
            LinkCopy(
              url: URL(string: "https://www.rfc-editor.org/rfc/rfc7932#section-4.2")!,
              label: "RFC 7932: Brotli Compressed Data Format")))
      #expect(items.opensInNewTab)
    }

    /// An anchor scrolls the document already on screen, and a tab of the same
    /// document is not what a tab means (`LinkDestination`).
    @Test func `an anchor in this document copies its public URL and opens no tab`() {
      let items = items("\(DocumentTextBuilder.anchorScheme):section-4.2")
      #expect(
        items.copyLink.publicLink?.url.absoluteString
          == "https://www.rfc-editor.org/rfc/rfc9110#section-4.2")
      #expect(!items.opensInNewTab)
    }

    @Test func `a bibliography entry copies the URL it names and opens no tab`() {
      let items = items("\(DocumentTextBuilder.referenceScheme):ISO.8601")
      #expect(
        items.copyLink.publicLink?.url.absoluteString
          == "https://www.iso.org/iso-8601-date-and-time-format.html")
      #expect(!items.opensInNewTab)
    }

    @Test func `a bibliography entry that names no URL has no Copy Link`() {
      #expect(items("\(DocumentTextBuilder.referenceScheme):Unlinked").copyLink == .none)
    }

    @Test func `a link to the web keeps the text view's Copy Link`() {
      let items = items("https://www.iana.org/assignments/")
      #expect(items.copyLink == .system)
      #expect(!items.opensInNewTab)
    }

    /// A link to the web is anyone's already, even one that names an RFC: its errata
    /// page is not the RFC's info page.
    @Test func `a web link that names an RFC keeps the text view's Copy Link`() {
      #expect(items("https://www.rfc-editor.org/errata/rfc9110").copyLink == .system)
    }

    @Test func `the added items go above Copy Link, which is replaced in place`() {
      let menu = textViewMenu()
      let copy = NSMenuItem(title: "Copy Link", action: nil, keyEquivalent: "")
      let tab = NSMenuItem(title: "Open in New Tab", action: nil, keyEquivalent: "")
      let preview = NSMenuItem(title: "Preview", action: nil, keyEquivalent: "")

      let adapted = LinkMenu.adapting(menu, copyLink: .replaced(copy), adding: [tab, preview])

      #expect(
        adapted.items.map(\.title) == [
          "Open Link", "Open in New Tab", "Preview", "Copy Link", "", "Copy",
        ])
      #expect(adapted.items[3] === copy)
      #expect(menu.items.count == 4, "AppKit may hand the same menu out again")
    }

    /// A heading's backlink caption (#183): its URL means nothing outside the reader.
    @Test func `a removed Copy Link leaves the rest of the menu`() {
      let adapted = LinkMenu.adapting(textViewMenu(), copyLink: .removed, adding: [])
      #expect(adapted.items.map(\.title) == ["Open Link", "", "Copy"])
    }

    @Test func `the text view's own Copy Link can stay`() {
      let adapted = LinkMenu.adapting(textViewMenu(), copyLink: .system, adding: [])
      #expect(adapted.items.map(\.action) == textViewMenu().items.map(\.action))
    }
  }
#endif
