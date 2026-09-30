import Foundation
import RFCKit

/// Which open tab a link from outside the app lands in: a URL, a script, the
/// Open RFC intent.
public enum LinkRouting {
  /// The tab already showing `document` if there is one, otherwise the preferred
  /// tab, otherwise the most recently used; nil with no tab open, when a window has
  /// to be opened for it. Of several tabs showing `document`, the preferred one.
  ///
  /// `scenes` are most recently used first, and `showing` is what each one has
  /// selected. `isPreferred` picks the tab of the window that was key last, on
  /// macOS: a tab opened behind it, or a script navigating another window, becomes
  /// the most recently used without being the one the reader is in (#277).
  public static func target<Scene>(
    for document: DocumentID, in scenes: [Scene], showing: (Scene) -> DocumentID?,
    preferring isPreferred: (Scene) -> Bool = { _ in false }
  ) -> Scene? {
    scenes.first { showing($0) == document && isPreferred($0) }
      ?? scenes.first { showing($0) == document }
      ?? scenes.first(where: isPreferred)
      ?? scenes.first
  }
}
