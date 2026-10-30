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

/// Next Section, Previous Section and Go to Section… (#711): in Focus the first two
/// move the focus (#699); in any other mode they go to the next or previous heading,
/// or in the outline the row.
struct SectionSteps: View {
  let reader: ReaderState
  /// Whether the items carry their shortcuts. iOS's More menu shows them without, as
  /// its Find in Document does: `DocumentCommands`' copies in the menu bar register
  /// them, so each chord is registered once.
  var showsShortcuts = true

  var body: some View {
    // ⌥⌘↓ and ⌥⌘↑: the text view's arrows take ⌘ to the document's ends and ⌥ to
    // its paragraphs' ends, and leave the two together alone.
    Button("Next Section", systemImage: "chevron.down") { reader.stepSection(.next) }
      .keyboardShortcut(showsShortcuts ? ReaderShortcut.nextSection.keyboardShortcut : nil)
      .disabled(!reader.canStepSection(.next))
    Button("Previous Section", systemImage: "chevron.up") { reader.stepSection(.previous) }
      .keyboardShortcut(showsShortcuts ? ReaderShortcut.previousSection.keyboardShortcut : nil)
      .disabled(!reader.canStepSection(.previous))
    // Over the original text too: it goes where the contents panel's rows go.
    Button("Go to Section…", systemImage: "number") { reader.isGoingToSection = true }
      .keyboardShortcut(showsShortcuts ? ReaderShortcut.goToSection.keyboardShortcut : nil)
      .disabled(reader.sections.isEmpty)
  }
}
