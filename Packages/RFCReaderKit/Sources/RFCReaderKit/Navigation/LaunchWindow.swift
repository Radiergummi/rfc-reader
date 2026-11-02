/// Whether the Mac app opens a reader window of its own at launch (#762, #939).
///
/// Only when no reader window came back from the last session, and not for a launch
/// that hid the app: a script launches it hidden, to ask it something, and a window
/// made then was left behind. AppKit's `launchIsDefaultUserInfoKey` alone can't tell
/// the two apart: AppKit sets it to false whenever the last session left state to
/// restore, even with no reader window in it, so a launch from the Dock after quitting
/// with every reader window closed opened none.
public enum LaunchWindow {
  public static func opens(readerCameBack: Bool, launchIsDefault: Bool, launchedHidden: Bool)
    -> Bool
  {
    if readerCameBack {
      return false
    }
    return launchIsDefault || !launchedHidden
  }
}
