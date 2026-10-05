import RFCReaderKit
import SwiftUI
import UniformTypeIdentifiers

/// The one place a copy reaches the pasteboard (#778). What goes on it is
/// `PasteboardContent`'s, the same on both platforms; this only writes it.
enum Clipboard {
  static func copy(_ string: String) {
    write(.text(string))
  }

  /// Copies `string`, and says that it worked.
  static func copy(_ string: String, announcing feedback: CopyFeedback) {
    write(.text(string), announcing: feedback)
  }

  /// Puts `content` on the pasteboard as one item, and says that the copy worked
  /// where it was one of the reader's own commands.
  static func write(_ content: PasteboardContent, announcing feedback: CopyFeedback? = nil) {
    #if os(macOS)
      let item = NSPasteboardItem()
      for flavor in content.flavors {
        let type = NSPasteboard.PasteboardType(flavor.type.identifier)
        switch flavor.value {
        case .text(let text): item.setString(text, forType: type)
        case .data(let data): item.setData(data, forType: type)
        }
      }
      NSPasteboard.general.clearContents()
      NSPasteboard.general.writeObjects([item])
    #else
      var item: [String: Any] = [:]
      for flavor in content.flavors {
        switch flavor.value {
        // UIKit reads a URL flavor only as a URL.
        case .text(let text) where flavor.type == .url:
          item[flavor.type.identifier] = URL(string: text)
        case .text(let text): item[flavor.type.identifier] = text
        case .data(let data): item[flavor.type.identifier] = data
        }
      }
      UIPasteboard.general.setItems([item])
    #endif
    if let feedback { announce(feedback) }
  }

  /// Says that a copy worked (#777): VoiceOver hears what was copied, and on iOS a
  /// success haptic stands in for the menu that just closed. Nothing is drawn: the
  /// HIG gives a copy from a menu no toast.
  static func announce(_ feedback: CopyFeedback) {
    #if os(macOS)
      // Posted on the app, not a view: a menu's action runs with the menu gone, and
      // the copy may come from a toolbar, a sheet or the menu bar.
      NSAccessibility.post(
        element: NSApp as Any, notification: .announcementRequested,
        userInfo: [
          .announcement: feedback.announcement(),
          .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    #else
      UIAccessibility.post(notification: .announcement, argument: feedback.announcement())
      UINotificationFeedbackGenerator().notificationOccurred(.success)
    #endif
  }
}
