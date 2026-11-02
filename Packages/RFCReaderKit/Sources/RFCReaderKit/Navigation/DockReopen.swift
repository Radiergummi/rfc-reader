/// What a click on the Dock icon of the running Mac app does (#365, #939), by what its
/// reader windows show. The settings or the primer's window left open alone do not
/// count as a reader.
///
/// A script launches the app hidden, and the last session's windows with it. Whatever
/// the app's state, the caller unhides it first, without activating it: the Dock
/// activates the app, which unhides it too, but nothing promises that this happens
/// before the reopen event arrives. Unhiding brings back every window that isn't
/// minimized, so in a hidden app those count as shown: one per tab group, its selected
/// tab. A tab group comes back minimized as a whole, and its other tabs, which AppKit
/// only orders out, count for nothing.
///
/// AppKit's `hasVisibleWindows` is not an input: it counts the settings, and is false
/// for a hidden app whose readers are about to come back.
public enum DockReopen: Equatable, Sendable {
  /// A reader window, as the Dock icon is clicked.
  public enum Reader: Equatable, Sendable {
    case visible
    case minimized
    /// Neither: made and not yet shown, or in a hidden app.
    case notShown
    /// A tab its group doesn't show: the group counts by its selected tab.
    case unselectedTab
  }

  /// Unhiding the app was all it took.
  case nothing
  /// A reader is in view: AppKit's own handling, which does nothing more.
  case appKitActs
  /// Bring back a minimized reader.
  case deminiaturize
  case openWindow

  public static func action(appIsHidden: Bool, readers: [Reader]) -> DockReopen {
    if appIsHidden, readers.contains(where: { $0 == .visible || $0 == .notShown }) {
      return .nothing
    }
    if readers.contains(.visible) {
      return .appKitActs
    }
    if readers.contains(.minimized) {
      return .deminiaturize
    }
    return .openWindow
  }
}
