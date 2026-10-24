import RFCReaderKit
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
          // An image, not a `Label`: with a label, iOS 26 never shows a toolbar
          // item's popover tip (#782).
          Image(systemName: "number")
            .accessibilityLabel("Go to RFC")
        }
        // After searches typed one after another, for an RFC known by its number or
        // title (#782).
        .helpTip(GoToRFCTip(), arrowEdge: .bottom)
      }
    }
  }
#endif
