import CoreSpotlight
import RFCKit
import RFCReaderKit
import SwiftData
import SwiftUI

@main
struct RFCReaderApp: App {
  #if !os(macOS)
    /// The one library. The app is a composition root, where `.shared` is reached
    /// for; what it makes hands the library on.
    @State private var library = LibraryModel.shared
  #else
    /// Windows are made by the delegate. macOS has no `WindowGroup` at all: the
    /// contents panel has to be a real `NSSplitViewItem` in the window's own split
    /// view controller for the tab bar and the toolbar to be confined by it, and a
    /// window `WindowGroup` made cannot be given one — see `ReaderWindowController`.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  #endif

  var body: some Scene {
    #if os(macOS)
      // The only scene, and still enough to carry the menu bar: `.commands` are
      // honored with no `WindowGroup` present, measured, which is what keeps the
      // whole menu from having to be rebuilt in AppKit. What it does not carry is
      // File ▸ New Window, which `WindowGroup` used to contribute — `WindowCommands`
      // puts it back.
      Settings {
        SettingsView()
      }
      .commands {
        AboutCommands()
        WindowCommands()
        DocumentCommands()
        #if DEBUG
          DeveloperCommands()
        #endif
      }
    #else
      // Deliberately plain: neither `WindowGroup(id:)` nor `WindowGroup(for:)`
      // opens a window at launch — measured, both leave the app running with no
      // interface at all — so this cannot carry the link for a new tab.
      WindowGroup {
        ContentView(library: library)
          .task { await library.bootstrap() }
          .onOpenURL { url in
            // rfc://9110#section-4.2, plus rfc-editor.org and datatracker
            // links handed over via the share sheet or Universal Links later.
            //
            // Every open scene receives this, so the routing decision cannot
            // be made here: `LibraryModel` holds the registry and picks
            // exactly one scene to act on it.
            if let link = RFCLink(url: url) {
              library.route(link)
            }
          }
          // An RFC chosen in Spotlight (#178), routed the same way.
          .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let id = SpotlightEntry.documentID(from: activity) {
              library.route(RFCLink(id: id))
            }
          }
      }
      .commands {
        DocumentCommands(library: library)
      }
    #endif
  }
}
