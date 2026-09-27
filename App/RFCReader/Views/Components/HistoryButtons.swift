import SwiftUI

/// Back and Forward through the scene's history, in the bar beside the sidebar.
/// Dimmed when there is nowhere to go rather than removed, as Safari does.
struct HistoryButtons: View {
  @Environment(NavigationModel.self) private var navigation

  var body: some View {
    Button {
      navigation.goBack()
    } label: {
      Label("Back", systemImage: "chevron.backward")
    }
    .disabled(!navigation.canGoBack)

    Button {
      navigation.goForward()
    } label: {
      Label("Forward", systemImage: "chevron.forward")
    }
    .disabled(!navigation.canGoForward)
  }
}
