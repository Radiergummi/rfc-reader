import RFCReaderKit
import SwiftUI
import TipKit

/// The Reading Mode menu (#698): View > Reading Mode on the Mac, and in the reader's
/// More menu on iOS. The Mac's More menu has it too, as AppKit items
/// (`ReaderToolbar`), both through `ReaderState.choose(_:)`.
struct ReadingModePicker: View {
  let reader: ReaderState

  var body: some View {
    Picker(
      "Reading Mode",
      selection: Binding(
        get: { reader.folding.mode },
        set: { reader.choose($0) })
    ) {
      ForEach(ReadingMode.allCases) { mode in
        Text(verbatim: mode.name()).tag(mode)
      }
    }
    .pickerStyle(.menu)
  }
}

extension ReaderState {
  /// Chooses a reading mode. It starts with nothing expanded, but for Focus becoming
  /// the outline, which keeps its section open (`Folding.switching(to:in:)`);
  /// choosing the one in use leaves it as it is. Either way the reader has found
  /// the modes, so their tip has no more to say (#782).
  func choose(_ mode: ReadingMode) {
    ReadingModeTip().invalidate(reason: .actionPerformed)
    guard mode != folding.mode else { return }
    // Focus starts on the section being read, which the text view knows, the
    // abstract included.
    // Focus is the one mode that keeps anything, and its folding index is there.
    folding = foldingIndex.map { folding.switching(to: mode, in: $0) } ?? Folding(mode: mode)
  }
}

/// Expand Section and Collapse Section, which open and close the outline's section
/// at the reader's line, for whoever does not point at its heading (#760). No
/// shortcut: the reader's keys are #711's to give.
struct OutlineSectionItems: View {
  let reader: ReaderState

  var body: some View {
    if reader.folding.mode == .outline {
      let section = reader.outlineSection
      Button("Expand Section", systemImage: "chevron.forward") {
        reader.setOutlineSection(expanded: true)
      }
      .disabled(section == nil || section?.isExpanded == true)
      Button("Collapse Section", systemImage: "chevron.down") {
        reader.setOutlineSection(expanded: false)
      }
      .disabled(section?.isExpanded != true)
    }
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
        .keyboardShortcut(ReaderShortcut.nextSection.keyboardShortcut)
        .disabled(!reader.canStepFocus(.next))
      Button("Previous Section", systemImage: "chevron.up") { reader.stepFocus(.previous) }
        .keyboardShortcut(ReaderShortcut.previousSection.keyboardShortcut)
        .disabled(!reader.canStepFocus(.previous))
    }
  }
}
