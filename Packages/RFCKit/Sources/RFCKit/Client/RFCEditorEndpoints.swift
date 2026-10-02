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

  /// An Internet-Draft's page on datatracker, `/doc/draft-ietf-httpbis-rfc6265bis/`,
  /// named without its revision.
  public static func datatrackerDraft(_ name: String) -> URL {
    datatrackerBase.appending(path: "doc/\(name)/")
  }

  /// `revisions.json`: adopted drafts that intend to obsolete or update an RFC, which
  /// the revisions workflow publishes daily on the repository's `revisions` release.
  public static let revisions = URL(
    string: "https://github.com/Radiergummi/rfc-reader/releases/download/revisions/revisions.json")!

  /// `groups.json`: the groups the index names, as datatracker describes them (#363),
  /// published beside `revisions.json` by the same daily workflow.
  public static let workingGroups = URL(
    string: "https://github.com/Radiergummi/rfc-reader/releases/download/revisions/groups.json")!
}
