import RFCKit
import RFCReaderKit
import SwiftUI

/// Help ▸ RFC Reader Help (#780), in place of the system's item, which looks for a
/// help book the app does not have. On the Mac it opens the help's window, and the
/// primer has an item of its own; on the iPad it presents the help as a sheet in the
/// focused scene.
struct HelpCommands: Commands {
  #if !os(macOS)
    @FocusedValue(\.showHelpAction) private var showHelp
  #endif

  var body: some Commands {
    CommandGroup(replacing: .help) {
      #if os(macOS)
        Button(HelpContent.title()) { HelpWindow.show() }
          .keyboardShortcut(ReaderShortcut.help.keyboardShortcut)
        Button(Glossary.primerTitle()) { PrimerWindow.show() }
      #else
        Button(HelpContent.title()) { showHelp?() }
          .keyboardShortcut(ReaderShortcut.help.keyboardShortcut)
          .disabled(showHelp == nil)
      #endif
    }
  }
}
