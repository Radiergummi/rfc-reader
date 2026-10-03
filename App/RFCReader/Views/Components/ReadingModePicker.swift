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
          // Focus starts on the section being read.
          reader.folding =
            mode == .focus ? Folding(focusingOn: reader.currentAnchor) : Folding(mode: mode)
        })
    ) {
      ForEach(ReadingMode.allCases) { mode in
        Text(mode.name).tag(mode)
      }
    }
    .pickerStyle(.menu)
  }
}

/// Next Section and Previous Section, which move the focus in Focus (#699).
struct FocusSteps: View {
  let reader: ReaderState

  var body: some View {
    if reader.folding.mode == .focus {
      Button("Next Section", systemImage: "chevron.down") { reader.stepFocus(.next) }
        .disabled(!reader.canStepFocus(.next))
      Button("Previous Section", systemImage: "chevron.up") { reader.stepFocus(.previous) }
        .disabled(!reader.canStepFocus(.previous))
    }
  }
}
