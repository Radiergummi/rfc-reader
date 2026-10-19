import Foundation

/// Where a link the app hands out points (#712): Share, Copy Link and every citation
/// link to the chosen site, and `RFCLink` reads each of them back.
///
/// One choice of site rather than of URL shape: the RFC Editor's own pages keep
/// their split, the info page for a document and the document itself for a section,
/// because the info page has no section anchors.
public enum LinkSite: String, CaseIterable, Sendable, Identifiable {
  /// `www.rfc-editor.org/info/rfc9110`, and `/rfc/rfc9110#section-4.2` for a section.
  case rfcEditor
  /// `datatracker.ietf.org/doc/html/rfc9110#section-4.2`.
  case datatracker
  /// `www.ietf.org/rfc/rfc9110.txt`: the plain text, which has no anchors, so a link
  /// to a section is a link to the document.
  case ietf
  /// The app's own `rfc://9110#section-4.2`, which opens nowhere else.
  case app

  public var id: String { rawValue }

  /// The address of `link` on this site: its section, or else its anchor, as the
  /// site's fragment, where the site has fragments.
  ///
  /// A series has no page of its own sections on the web, the RFC Editor's
  /// `rfc/bcp14#section-2` is no page at all, so its link is to the series. The
  /// app opens a series at a section.
  public func url(for link: RFCLink) -> URL {
    let link = link.id.series == .rfc || self == .app ? link : RFCLink(id: link.id)
    switch self {
    case .rfcEditor:
      guard link.section == nil, let anchor = link.anchor else {
        guard let section = link.section else { return RFCEditorEndpoints.infoPage(link.id) }
        return RFCLink.url(Self.rfcEditorDocument(link.id), section: section)
      }
      // The document's page, which defines the anchor, rather than its info page.
      return RFCLink.url(Self.rfcEditorDocument(link.id), fragment: anchor)
    case .datatracker:
      let page = RFCEditorEndpoints.datatrackerBase.appending(path: "doc/html/\(link.id.fileStem)")
      return RFCLink.url(page, fragment: fragment(of: link))
    case .ietf:
      // ietf.org has no copy of an STD or an FYI, and its BCP's redirects to the
      // series' page at the RFC Editor: a series links there.
      guard link.id.series == .rfc else { return RFCEditorEndpoints.infoPage(link.id) }
      return Self.ietfBase.appending(path: "rfc/\(link.id.fileStem).txt")
    case .app:
      return link.appURL
    }
  }

  /// `section-4.2` for a section, an anchor as it is.
  private func fragment(of link: RFCLink) -> String? {
    link.section.map(SectionAnchor.anchor(forSectionNumber:)) ?? link.anchor
  }

  private static func rfcEditorDocument(_ id: DocumentID) -> URL {
    RFCEditorEndpoints.base.appending(path: "rfc/\(id.fileStem)")
  }

  private static let ietfBase = URL(string: "https://www.ietf.org")!
}
