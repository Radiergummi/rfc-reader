import RFCReaderKit
import SwiftUI

struct OriginalTextView: View {
  #if canImport(UIKit)
    @Environment(ReaderState.self) private var reader
  #endif
  /// For the page theme, which is the light one or the dark one by the appearance
  /// (#704).
  @ReaderSettingsValue private var settings
  @Environment(\.colorScheme) private var colorScheme
  let text: String?
  let failure: LoadFailure?
  let fontSize: Double
  /// Whether this is the reader on screen, whose text Find opens over on iOS (#763),
  /// rather than one the stack keeps below its top.
  let isShown: Bool
  let tryAgain: () -> Void

  var body: some View {
    if let text {
      #if canImport(UIKit)
        OriginalTextBody(
          text: text, fontSize: fontSize, settings: settings,
          appearance: PaletteAppearance(colorScheme), reader: isShown ? reader : nil)
      #else
        OriginalTextBody(
          text: text, fontSize: fontSize, settings: settings,
          appearance: PaletteAppearance(colorScheme))
      #endif
    } else if let failure {
      ContentUnavailableView {
        Label("Couldn’t Load the Original Text", systemImage: failure.kind.symbol)
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
