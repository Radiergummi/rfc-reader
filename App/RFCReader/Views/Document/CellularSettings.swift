#if !os(macOS)
  import UIKit

  /// The app's page in Settings, where its cellular data switch is: what a load that
  /// failed with `LoadFailure.Kind.cellularDenied` offers to open (#759).
  enum CellularSettings {
    /// Through `UIApplication` rather than `openURL`, which the reader answers with
    /// its own handler for links.
    static func open() {
      guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
      UIApplication.shared.open(url)
    }
  }
#endif
