import RFCReaderKit
import SwiftUI

#if os(macOS)
  /// The About panel, crediting the code the app includes or adapts, as its licenses
  /// ask, and Check for Updates… beside it, where a Mac app keeps it (#911).
  struct AboutCommands: Commands {
    @State private var updater = Updater.shared

    var body: some Commands {
      CommandGroup(replacing: .appInfo) {
        Button("About RFC Reader") {
          let credits = NSAttributedString(
            string: Acknowledgements.text,
            attributes: [
              .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
              .foregroundColor: NSColor.labelColor,
            ])
          NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        }
        Button("Check for Updates…") {
          updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
      }
    }
  }
#endif
