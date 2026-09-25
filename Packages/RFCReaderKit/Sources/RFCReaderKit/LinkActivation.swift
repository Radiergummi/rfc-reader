#if canImport(AppKit)
import AppKit
#endif

/// What a click on a reference is asking for.
///
/// The modifier conventions are the browser's, because that is what a reader's hands
/// already know: Command opens elsewhere and stays put, and Shift means "and take me
/// there".
public enum LinkActivation: Equatable, Sendable {
    /// Follow it here, replacing what is on screen.
    case here
    /// A tab of its own, either left behind the current one or brought to the front.
    case newTab(inBackground: Bool)

    /// Reads the intent off the modifiers held at the moment of the click.
    ///
    /// A pure function of the two flags, so the mapping is testable without a click:
    /// the App target has no test bundle, and getting Command-Shift to mean
    /// "foreground" rather than "background" is exactly the sort of mistake that only
    /// shows up under the fingers.
    public init(command: Bool, shift: Bool) {
        guard command || shift else {
            self = .here
            return
        }
        self = .newTab(inBackground: command && !shift)
    }
}

extension LinkActivation {
    /// The modifiers held right now.
    ///
    /// The one place the app asks. Most gestures carry no event of their own — a
    /// SwiftUI `Button` action runs after the click is over, and `NSTextView`'s
    /// `clickedOnLink:` is handed no event either — so the flags are read from the
    /// click still being dispatched, falling back to the keyboard's current state
    /// when there is no event at all. UIKit publishes neither, so every tap reads as
    /// a plain one: opening a reference elsewhere is the long-press menu's job there,
    /// not a chord's.
    @MainActor
    public static var current: LinkActivation {
        #if canImport(AppKit)
        let flags = NSApp?.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
        return LinkActivation(command: flags.contains(.command), shift: flags.contains(.shift))
        #else
        return .here
        #endif
    }
}
