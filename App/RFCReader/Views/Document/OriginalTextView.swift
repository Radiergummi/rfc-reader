import RFCReaderKit
import SwiftUI

struct OriginalTextView: View {
  let text: String?
  let failure: LoadFailure?
  let fontSize: Double
  let tryAgain: () -> Void

  var body: some View {
    if let text {
      OriginalTextBody(text: text, fontSize: fontSize)
    } else if let failure {
      ContentUnavailableView {
        Label("Couldn't load the original text", systemImage: failure.kind.symbol)
      } description: {
        Text(failure.message)
        Text(failure.kind.recoverySuggestion(for: .originalText))
      } actions: {
        Button("Try Again", action: tryAgain)
        #if !os(macOS)
          if failure.kind == .cellularDenied {
            Button("Open Settings", action: CellularSettings.open)
          }
        #endif
      }
    } else {
      ProgressView()
    }
  }
}
