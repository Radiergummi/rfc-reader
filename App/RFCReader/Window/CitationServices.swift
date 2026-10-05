#if os(macOS)
  import AppKit
  import RFCKit

  /// The two Services `project.yml` declares under `NSServices` (#195), offered in
  /// every app for selected text: "Replace with RFC Link" turns `RFC 9110 §8.3` into
  /// `rfc://9110#section-8.3` where it stands, and "Open in RFC Reader" opens it here.
  ///
  /// Which citation a selection makes is `CitationLink`'s to say, where it is tested;
  /// this only moves text between the pasteboard and the library. A selection that
  /// cites no one place is left as it was: Services cannot hide themselves for one
  /// selection, so the item stays in the menu and reports why it did nothing.
  final class CitationServices: NSObject {
    /// `NSMessage` `replaceWithRFCLink`.
    @objc func replaceWithRFCLink(
      _ pasteboard: NSPasteboard, userData: String?,
      error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
      guard let selection = pasteboard.string(forType: .string),
        let replacement = CitationLink.replacement(for: selection)
      else {
        error.pointee = Self.noCitation
        return
      }
      pasteboard.clearContents()
      pasteboard.setString(replacement, forType: .string)
    }

    /// `NSMessage` `openInRFCReader`. A Service runs without bringing its app forward,
    /// so the app is activated for the window the link opens in.
    @objc func openInRFCReader(
      _ pasteboard: NSPasteboard, userData: String?,
      error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
      guard let selection = pasteboard.string(forType: .string),
        let link = CitationLink.link(in: selection)
      else {
        error.pointee = Self.noCitation
        return
      }
      NSApp.activate()
      LibraryModel.shared.route(link)
    }

    private static let noCitation: NSString =
      "The selection does not cite a single RFC, such as “RFC 9110 §8.3” or “[RFC9110]”."
  }
#endif
