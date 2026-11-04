import RFCKit
import RFCReaderKit
import SwiftUI

/// A list row's Keep Offline item, in the Mac's context menu and the iPhone's
/// alike (#358): it marks the document, or removes its mark.
struct KeepOfflineButton: View {
  let document: DocumentID
  let library: LibraryModel

  private var isKept: Bool { library.userData.offlineMarks.contains(document) }

  var body: some View {
    Button {
      library.documents.setKeptOfflineInBackground(document, !isKept)
    } label: {
      Label(
        DocumentActions.keepOfflineCommand(isKept: isKept),
        systemImage: DocumentActions.keepOfflineSymbol(isKept: isKept))
    }
  }
}
