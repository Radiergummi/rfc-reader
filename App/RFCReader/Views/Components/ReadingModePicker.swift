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
          // Focus starts on the section being read, which the text view knows, the
          // abstract included.
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

/// Next Section and Previous Section, which move the focus in Focus (#699).
struct FocusSteps: View {
  let reader: ReaderState

  var body: some View {
    // Not over the original text, which nothing folds: there is no folding index
    // then, so nowhere to step (`DocumentView.updateFolding`).
    if reader.folding.mode == .focus {
      // ⌥⌘↓ and ⌥⌘↑: the text view's arrows take ⌘ to the document's ends and ⌥ to
      // its paragraphs' ends, and leave the two together alone.
      Button("Next Section", systemImage: "chevron.down") { reader.stepFocus(.next) }
        .keyboardShortcut(.downArrow, modifiers: [.command, .option])
        .disabled(!reader.canStepFocus(.next))
      Button("Previous Section", systemImage: "chevron.up") { reader.stepFocus(.previous) }
        .keyboardShortcut(.upArrow, modifiers: [.command, .option])
        .disabled(!reader.canStepFocus(.previous))
    }
  }
}
