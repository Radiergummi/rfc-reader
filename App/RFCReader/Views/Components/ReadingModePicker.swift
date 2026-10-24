import RFCReaderKit
import SwiftUI

/// The Reading Mode menu (#698): View > Reading Mode on the Mac, and in the reader's
/// More menu on iOS. Choosing a mode starts it with nothing expanded, but for Focus
/// becoming the outline, which keeps its section open (`Folding.switching(to:in:)`);
/// choosing the one in use leaves it as it is.
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
          // Focus is the one mode that keeps anything, and its folding index is there.
          reader.folding =
            reader.foldingIndex.map { reader.folding.switching(to: mode, in: $0) }
            ?? Folding(mode: mode)
        })
    ) {
      ForEach(ReadingMode.allCases) { mode in
        Text(verbatim: mode.name()).tag(mode)
      }
    }
    .pickerStyle(.menu)
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

/// Next Section, Previous Section and Go to Section… (#711): in Focus the first two
/// move the focus (#699); in any other mode they go to the next or previous heading,
/// or in the outline the row.
struct SectionSteps: View {
  let reader: ReaderState

  var body: some View {
    // ⌥⌘↓ and ⌥⌘↑: the text view's arrows take ⌘ to the document's ends and ⌥ to
    // its paragraphs' ends, and leave the two together alone.
    Button("Next Section", systemImage: "chevron.down") { reader.stepSection(.next) }
      .keyboardShortcut(ReaderShortcut.nextSection.keyboardShortcut)
      .disabled(!reader.canStepSection(.next))
    Button("Previous Section", systemImage: "chevron.up") { reader.stepSection(.previous) }
      .keyboardShortcut(ReaderShortcut.previousSection.keyboardShortcut)
      .disabled(!reader.canStepSection(.previous))
    // Over the original text too: it goes where the contents panel's rows go.
    Button("Go to Section…", systemImage: "number") { reader.isGoingToSection = true }
      .keyboardShortcut(ReaderShortcut.goToSection.keyboardShortcut)
      .disabled(reader.sections.isEmpty)
  }
}
