import RFCReaderKit
import SwiftUI

#if os(macOS)
  /// What `WindowGroup` used to contribute to the File menu.
  struct WindowCommands: Commands {
    var body: some Commands {
      CommandGroup(replacing: .newItem) {
        Button("New Window") {
          AppDelegate.shared?.openWindow(tabbedWith: nil, inBackground: false)
        }
        .keyboardShortcut(ReaderShortcut.newWindow.keyboardShortcut)

        Button("New Tab") {
          AppDelegate.shared?.openTab(inBackground: false)
        }
        .keyboardShortcut(ReaderShortcut.newTab.keyboardShortcut)
      }
    }
  }
#endif
