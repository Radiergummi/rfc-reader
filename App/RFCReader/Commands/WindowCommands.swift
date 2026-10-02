import SwiftUI

#if os(macOS)
  /// What `WindowGroup` used to contribute to the File menu.
  struct WindowCommands: Commands {
    var body: some Commands {
      CommandGroup(replacing: .newItem) {
        Button("New Window") {
          AppDelegate.shared?.openWindow(tabbedWith: nil, inBackground: false)
        }
        .keyboardShortcut("n", modifiers: .command)

        Button("New Tab") {
          AppDelegate.shared?.openTab(inBackground: false)
        }
        .keyboardShortcut("t", modifiers: .command)
      }
    }
  }
#endif
