#if os(macOS)
  import Foundation
  import Sparkle

  /// Updates for the Mac app outside the App Store, through Sparkle (#911).
  ///
  /// The feed is `SUFeedURL` and the public half of the key its updates are signed
  /// with is `SUPublicEDKey`, both in `project.yml`. The app is sandboxed, so Sparkle
  /// installs through its launcher service.
  ///
  /// A Debug build never starts the updater, so it neither checks nor offers Check
  /// for Updates…: Sparkle installs over the running bundle, and an update accepted
  /// in a development build would replace it with the release. Not a setting, because
  /// Debug and Release share a bundle ID and so the defaults Sparkle reads first.
  @Observable
  final class Updater {
    static let shared = Updater()

    #if DEBUG
      private static let starts = false
    #else
      private static let starts = true
    #endif

    @ObservationIgnored private let controller = SPUStandardUpdaterController(
      startingUpdater: Updater.starts, updaterDelegate: nil, userDriverDelegate: nil)
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    /// False while a check or an update is under way, and in a Debug build, when
    /// Check for Updates… is disabled.
    private(set) var canCheckForUpdates = false

    private init() {
      canCheckObservation = controller.updater.observe(
        \.canCheckForUpdates, options: [.initial, .new]
      ) { [weak self] updater, _ in
        // Sparkle changes it on the main thread.
        MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
      }
    }

    func checkForUpdates() {
      controller.checkForUpdates(nil)
    }

    /// Sparkle keeps the setting in the app's defaults.
    var automaticallyChecksForUpdates: Bool {
      get {
        access(keyPath: \.automaticallyChecksForUpdates)
        return controller.updater.automaticallyChecksForUpdates
      }
      set {
        withMutation(keyPath: \.automaticallyChecksForUpdates) {
          controller.updater.automaticallyChecksForUpdates = newValue
        }
      }
    }
  }
#endif
