import RFCReaderKit
import SwiftUI

/// The Reading Mode menu (#698): View > Reading Mode on the Mac, and in the reader's
/// More menu on iOS. Choosing a mode starts it with nothing expanded; choosing the one
/// in use leaves it as it is.
struct ReadingModePicker: View {
  let reader: ReaderState

  var body: some View {
    Picker(
      "Reading Mode",
      selection: Binding(
        get: { reader.folding.mode },
        set: { mode in
          guard mode != reader.folding.mode else { return }
          reader.folding = Folding(mode: mode)
        })
    ) {
      ForEach(ReadingMode.allCases) { mode in
        Text(mode.name).tag(mode)
      }
    }
    .pickerStyle(.menu)
  }
}
