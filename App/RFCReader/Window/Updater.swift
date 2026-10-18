#if os(macOS)
  import Foundation
  import Sparkle

  /// Updates for the Mac app outside the App Store, through Sparkle (#911).
  ///
  /// The feed is `SUFeedURL` and the public half of the key its updates are signed
  /// with is `SUPublicEDKey`, both in `project.yml`. The app is sandboxed, so Sparkle
  /// installs through its launcher service.
  ///
  /// Only a build of `.github/scripts/release.sh`, which sets the compilation
  /// condition `SELF_UPDATING`, starts the updater; any other build neither checks
  /// nor offers Check for Updates…. Sparkle installs over the running bundle, so an
  /// update accepted in a local build, Debug or Release (`make install`, `make trace`),
  /// would replace it with the published release. Not a setting, because every build
  /// shares the bundle ID and so the defaults Sparkle reads first.
  @Observable
  final class Updater {
    static let shared = Updater()

    /// Whether this build runs the updater at all: only a release build does.
    #if SELF_UPDATING
      static let starts = true
    #else
      static let starts = false
    #endif

    @ObservationIgnored private let controller = SPUStandardUpdaterController(
      startingUpdater: Updater.starts, updaterDelegate: nil, userDriverDelegate: nil)
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    /// False while a check or an update is under way, and in any build but a release,
    /// when Check for Updates… is disabled.
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
