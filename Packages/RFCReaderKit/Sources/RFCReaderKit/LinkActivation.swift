import Foundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// What a click on a reference is asking for.
///
/// The modifier conventions are the browser's, because that is what a reader's hands
/// already know: Command opens elsewhere and stays put, adding Shift means "and take
/// me there", Shift alone opens a window of its own.
public enum LinkActivation: Equatable, Sendable {
    /// Follow it here, replacing what is on screen.
    case here
    /// A new tab behind the current one; the reader keeps reading.
    case newTabInBackground
    /// A new tab, brought to the front.
    case newTabInForeground
    /// A window of its own.
    case newWindow

    /// Reads the intent off the modifiers held at the moment of the click.
    ///
    /// A pure function of the flags, so the mapping is testable without a click: the
    /// App target has no test bundle, and getting Command-Shift to mean "foreground"
    /// rather than falling through to `newWindow` is exactly the sort of ordering
    /// mistake that only shows up under the fingers.
    public static func from(modifiers: ModifierKeys) -> LinkActivation {
        if modifiers.contains(.command) {
            return modifiers.contains(.shift) ? .newTabInForeground : .newTabInBackground
        }
        if modifiers.contains(.shift) {
            return .newWindow
        }
        return .here
    }

    /// Just the two flags that matter, named so the mapping above can be tested
    /// without conjuring an `NSEvent`.
    public struct ModifierKeys: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let command = ModifierKeys(rawValue: 1 << 0)
        public static let shift = ModifierKeys(rawValue: 1 << 1)

        #if !canImport(UIKit)
        /// Only AppKit builds one of these: a tap carries no modifiers.
        public init(_ flags: NSEvent.ModifierFlags) {
            var keys = ModifierKeys()
            if flags.contains(.command) { keys.insert(.command) }
            if flags.contains(.shift) { keys.insert(.shift) }
            self = keys
        }
        #endif
    }
}
