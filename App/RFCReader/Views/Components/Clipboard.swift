import RFCReaderKit
import SwiftUI

enum Clipboard {
  static func copy(_ string: String) {
    #if os(macOS)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(string, forType: .string)
    #else
      UIPasteboard.general.string = string
    #endif
  }

  /// Copies `string`, and says that it worked.
  static func copy(_ string: String, announcing feedback: CopyFeedback) {
    copy(string)
    announce(feedback)
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
          .announcement: feedback.announcement,
          .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    #else
      UIAccessibility.post(notification: .announcement, argument: feedback.announcement)
      UINotificationFeedbackGenerator().notificationOccurred(.success)
    #endif
  }
}
