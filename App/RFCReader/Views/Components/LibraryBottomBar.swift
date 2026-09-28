import SwiftUI

#if !os(macOS)
  /// The search field at the foot of the sidebar and the list, with Go to RFC beside
  /// it, where Notes keeps Compose beside its own (#345).
  ///
  /// Go to RFC was reachable only from the empty detail view, which an iPhone never
  /// shows, and from ⌘L.
  struct LibraryBottomBar: ToolbarContent {
    let navigation: NavigationModel

    var body: some ToolbarContent {
      DefaultToolbarItem(kind: .search, placement: .bottomBar)
      ToolbarSpacer(.fixed, placement: .bottomBar)
      ToolbarItem(placement: .bottomBar) {
        Button {
          navigation.isShowingGoToSheet = true
        } label: {
          Label("Go to RFC", systemImage: "number")
        }
      }
    }
  }
#endif
