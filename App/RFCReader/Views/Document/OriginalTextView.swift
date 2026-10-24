import RFCReaderKit
import SwiftUI

struct OriginalTextView: View {
  #if canImport(UIKit)
    @Environment(ReaderState.self) private var reader
  #endif
  let text: String?
  let failure: LoadFailure?
  /// What the text is of, which a failure's suggestion names: an RFC's, or a
  /// draft's, which is the IETF's (#728).
  let subject: LoadFailure.Subject
  let fontSize: Double
  /// Whether this is the reader on screen, whose text Find opens over on iOS (#763),
  /// rather than one the stack keeps below its top.
  let isShown: Bool
  let tryAgain: () -> Void

  var body: some View {
    if let text {
      #if canImport(UIKit)
        OriginalTextBody(text: text, fontSize: fontSize, reader: isShown ? reader : nil)
      #else
        OriginalTextBody(text: text, fontSize: fontSize)
      #endif
    } else if let failure {
      ContentUnavailableView {
        Label("Couldn’t Load the Original Text", systemImage: failure.kind.symbol)
      } description: {
        Text(failure.message)
        Text(failure.kind.recoverySuggestion(for: subject))
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
