import RFCKit
import RFCReaderKit
import SwiftUI

#if os(macOS)
  import AppKit
#endif

#if os(macOS) && DEBUG
  /// A developer's way in until packs have a Settings ▸ Offline of their own (#36):
  /// install the legacy XML pack from an `.aar` or an unpacked folder.
  struct DeveloperCommands: Commands {
    var body: some Commands {
      CommandMenu("Developer") {
        Button("Install Data Pack…") { Self.chooseAndInstall() }
      }
    }

    private static func chooseAndInstall() {
      let panel = NSOpenPanel()
      panel.message = "Choose a legacy XML pack: an .aar archive, or a folder with its manifest."
      panel.canChooseFiles = true
      panel.canChooseDirectories = true
      panel.allowsMultipleSelection = false
      guard panel.runModal() == .OK, let source = panel.url else { return }
      Task {
        let alert = NSAlert()
        do {
          // `.shared` on the click rather than handed over: the App holds no library
          // on macOS, so that launch makes it where `AppDelegate` does, no earlier.
          let pack = try await LibraryModel.shared.installLegacyPack(from: source)
          alert.messageText = "Installed Data Pack \(pack.manifest.version)"
          alert.informativeText = "\(pack.manifest.files.count) documents."
        } catch {
          alert.alertStyle = .warning
          alert.messageText = "Couldn’t Install the Data Pack"
          alert.informativeText = String(describing: error)
        }
        alert.runModal()
      }
    }
  }
#endif
