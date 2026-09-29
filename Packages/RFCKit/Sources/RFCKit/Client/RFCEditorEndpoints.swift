import Foundation

/// URL construction for the RFC Editor and IETF Datatracker. All of these were
/// verified live in September 2026; none require authentication.
public enum RFCEditorEndpoints {
  public static let base = URL(string: "https://www.rfc-editor.org")!
  public static let datatrackerBase = URL(string: "https://datatracker.ietf.org")!

  /// The full index, about 14 MB of XML covering every RFC, BCP, STD and FYI.
  public static var index: URL { base.appending(path: "rfc-index.xml") }

  /// RSS feed of recently published RFCs; cheap to poll for "what's new".
  public static var recentFeed: URL { base.appending(path: "rfcrss.xml") }

  /// The document body in the given format, e.g. `/rfc/rfc9110.xml`.
  public static func document(_ id: DocumentID, format: FileFormat) -> URL {
    base.appending(path: "rfc/\(id.fileStem).\(format.pathExtension)")
  }

  /// The human-facing landing page, the canonical thing to share.
  public static func infoPage(_ id: DocumentID) -> URL {
    base.appending(path: "info/\(id.fileStem)")
  }

  /// Datatracker's HTMLized rendering, which has anchors for every section and reference.
  public static func datatracker(_ id: DocumentID, section: String? = nil) -> URL {
    RFCLink.url(datatrackerBase.appending(path: "doc/html/\(id.fileStem)"), section: section)
  }
}
