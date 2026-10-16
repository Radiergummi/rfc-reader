#if os(macOS)
  import Foundation
  import Sparkle

  /// Updates for the Mac app outside the App Store, through Sparkle (#911).
  ///
  /// The feed is `SUFeedURL` and the public half of the key its updates are signed
  /// with is `SUPublicEDKey`, both in `project.yml`. Whether Sparkle checks on its own
  /// is `SUEnableAutomaticChecks`, off in Debug, until changed in Settings. The app is
  /// sandboxed, so Sparkle installs through its launcher service.
  @Observable
  final class Updater {
    static let shared = Updater()

    @ObservationIgnored private let controller = SPUStandardUpdaterController(
      startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    /// False while a check or an update is under way, when Check for Updates… is
    /// disabled.
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
