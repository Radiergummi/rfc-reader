import RFCReaderKit
import SwiftUI

/// Back and Forward through the scene's history, in the bar beside the sidebar.
/// Dimmed when there is nowhere to go rather than removed, as Safari does.
struct HistoryButtons: View {
  @Environment(NavigationModel.self) private var navigation

  var body: some View {
    Button {
      navigation.goBack()
    } label: {
      // An image, not a `Label`: with a label, iOS 26 never shows a toolbar item's
      // popover tip (#782).
      Image(systemName: "chevron.backward")
        .accessibilityLabel("Back")
    }
    .disabled(!navigation.canGoBack)
    // Once a citation has given Back somewhere to go: previews read it without
    // going (#782). Only beside other columns, the one place this is shown: an
    // iPhone has no Back of ours.
    .helpTip(PreviewTip(), isOffered: navigation.canGoBack)

    Button {
      navigation.goForward()
    } label: {
      Label("Forward", systemImage: "chevron.forward")
    }
    .disabled(!navigation.canGoForward)
  }
}
