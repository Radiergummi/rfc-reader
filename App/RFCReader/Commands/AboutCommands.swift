import RFCReaderKit
import SwiftUI

#if os(macOS)
  /// The About panel, crediting the code the app adapts, as its licenses ask.
  struct AboutCommands: Commands {
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
      }
    }
  }
#endif
