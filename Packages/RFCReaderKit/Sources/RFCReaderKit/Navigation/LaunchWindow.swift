/// When the Mac app opens a reader window of its own after launching (#762, #939):
/// only when no reader window came back from the last session, and only for a launch
/// the user sees.
///
/// A default launch, from the Finder or the Dock with nothing to restore, opens it at
/// once. Any other launch waits for the app's first activation. AppKit calls a launch
/// not the default one whenever the last session left state to restore, even with no
/// reader window in it, so a Dock launch after quitting with every reader window closed
/// is one. So is a launch by a script, a Service or a background intent, which never
/// activates the app and should leave no window behind. The Dock, the Finder and `open`
/// activate it, and so does the user switching to an app a script launched.
public struct LaunchWindow: Sendable {
  /// Whether to open the window as launch finishes.
  public let opensAtLaunch: Bool
  private var waitsForActivation: Bool

  public init(launchIsDefault: Bool, readerCameBack: Bool) {
    opensAtLaunch = launchIsDefault && !readerCameBack
    waitsForActivation = !launchIsDefault && !readerCameBack
  }

  /// The app became active: whether to open the window now. Once only, and not when a
  /// reader window has opened since launch, as a link that launched the app makes one.
  public mutating func becameActive(hasReaderWindow: Bool) -> Bool {
    guard waitsForActivation else { return false }
    waitsForActivation = false
    return !hasReaderWindow
  }
}
