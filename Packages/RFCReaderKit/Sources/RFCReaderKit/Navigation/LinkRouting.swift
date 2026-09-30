import Foundation
import RFCKit

/// Which open tab a link from outside the app lands in: a URL, a script, the
/// Open RFC intent.
public enum LinkRouting {
  /// The tab already showing `document` if there is one, otherwise the most
  /// recently used; nil with no tab open, when a window has to be opened for it.
  ///
  /// `scenes` are most recently used first, and `showing` is what each one has
  /// selected.
  public static func target<Scene>(
    for document: DocumentID, in scenes: [Scene], showing: (Scene) -> DocumentID?
  ) -> Scene? {
    scenes.first { showing($0) == document } ?? scenes.first
  }
}
