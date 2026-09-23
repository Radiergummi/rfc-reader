#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit

/// Which view should take first responder, in a window whose columns are separate
/// hosting roots.
///
/// Two searches in opposite directions, both pure functions of a view tree and a
/// starting point. They live in this package for the reason `FragmentGeometry` does:
/// the App target has no test bundle, and the interesting cases here are the ones
/// nobody clicks by hand — a hit that is already inside the responder, a walk that
/// reaches the root without finding a taker, a container whose content has not been
/// built yet. The window keeps the AppKit half: the event hook, the hit test, and
/// `makeFirstResponder`.
@MainActor
public enum FirstResponderSearch {
    /// The innermost view at or above `hit` that will take first responder.
    ///
    /// Upwards, because the deepest view under a click is usually a leaf that takes
    /// nothing — a SwiftUI cell, a label — while the view that wants focus is the
    /// list or the text view containing it. `root` bounds the walk so the search
    /// cannot escape into the window itself.
    ///
    /// Returns nil when `hit` already sits inside `current`, so a click inside the
    /// view that already has focus is left alone rather than re-focused.
    public static func target(from hit: NSView, upTo root: NSView, skipping current: NSResponder?) -> NSView? {
        if let focused = current as? NSView, hit.isDescendant(of: focused) { return nil }
        var view = hit
        while !view.acceptsFirstResponder {
            guard let parent = view.superview, parent !== root else { return nil }
            view = parent
        }
        return view
    }

    /// The deepest view inside `root` that will take first responder, or `root`
    /// itself if it will and nothing below it does.
    ///
    /// Downwards and depth first, because a hosting view answers
    /// `acceptsFirstResponder` on behalf of its whole content: a search that asked
    /// from the top would stop at the column and never reach the list inside it.
    public static func innermostTarget(in root: NSView) -> NSView? {
        for subview in root.subviews {
            if let found = innermostTarget(in: subview) { return found }
        }
        return root.acceptsFirstResponder ? root : nil
    }
}
#endif
