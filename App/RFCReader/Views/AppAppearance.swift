import RFCReaderKit
import SwiftUI

#if os(macOS)
  import AppKit

  /// The appearance setting (#704), applied to the whole app as Apple Books applies
  /// its own: every window, the settings and the panels with them, not only the
  /// page. On the Mac that is the application's appearance, which every window
  /// inherits.
  @MainActor
  enum AppAppearance {
    /// Applies the setting now and again whenever user defaults change, for as long
    /// as the app runs: Settings writes it, and nothing else needs telling.
    static func follow() {
      apply()
      NotificationCenter.default.addObserver(
        forName: UserDefaults.didChangeNotification, object: nil, queue: .main
      ) { _ in
        MainActor.assumeIsolated { apply() }
      }
    }

    private static func apply() {
      // The one key, not the whole settings: this runs on every write to defaults.
      let stored = UserDefaults.standard.string(forKey: ReaderPreferences.appearanceKey)
      let forced = stored.flatMap(AppearancePreference.init)?.forced
      let appearance: NSAppearance? =
        switch forced {
        case nil: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
      // Only a change: setting it redraws every window.
      guard NSApp.appearance?.name != appearance?.name else { return }
      NSApp.appearance = appearance
    }
  }
#else
  import UIKit

  /// The appearance setting (#704), applied to the whole app as Apple Books applies
  /// its own: every window of every scene, not only the page. On iOS that is each
  /// window's interface style, which its sheets and popovers inherit.
  struct AppAppearance: ViewModifier {
    @AppStorage(ReaderPreferences.appearanceKey) private var appearance =
      ReaderPreferences.defaultAppearance

    func body(content: Content) -> some View {
      // Every scene's windows, since each scene's root applies it, and a scene made
      // after a change applies it as it appears.
      content.onChange(of: appearance, initial: true) {
        let style: UIUserInterfaceStyle =
          switch appearance.forced {
          case nil: .unspecified
          case .light: .light
          case .dark: .dark
          }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
          for window in scene.windows { window.overrideUserInterfaceStyle = style }
        }
      }
    }
  }
#endif
