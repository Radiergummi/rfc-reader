import Foundation
import RFCKit

/// What the reader's header says of an Internet-Draft it shows (#728): that it is a
/// draft and not an RFC, which revision it is, whether a newer one exists or it was
/// published, and the revisions to switch to.
public struct DraftStatus: Equatable, Sendable {
  /// The revision on screen.
  public let shown: DraftID
  /// What Datatracker says of the draft, nil until it has said, or offline with
  /// nothing kept.
  public let info: DraftInfo?
  private let locale: Locale

  public init(shown: DraftID, info: DraftInfo?, locale: Locale = .interface) {
    self.shown = shown
    self.info = info?.name == shown.name ? info : nil
    self.locale = locale
  }

  /// The mark beside the title, saying what this is not.
  public var mark: String {
    String(kit: "Internet-Draft, not an RFC", locale: locale)
  }

  /// "Revision 19", or the draft's name where it names no revision.
  public var revisionLabel: String {
    guard let revision = shown.revision else { return shown.name }
    return Self.revisionLabel(revision, locale: locale)
  }

  /// One sentence on where the revision stands: the RFC it became, the newer
  /// revision there is, or nil when it is the newest of a draft still a draft.
  public var notice: String? {
    guard let info else { return nil }
    if let rfc = info.publishedAs {
      return String(kit: "Published as \(rfc.displayName)", locale: locale)
    }
    guard let revision = shown.revision, revision != info.newestRevision else { return nil }
    let newest = Self.number(info.newestRevision)
    return String(kit: "Revision \(newest) is the newest", locale: locale)
  }

  /// The RFC the draft became, which the notice names.
  public var publishedAs: DocumentID? { info?.publishedAs }

  /// The newest revision, when the one on screen is not it.
  public var newer: DraftID? {
    guard let info, shown.revision != info.newestRevision else { return nil }
    return shown.at(revision: info.newestRevision)
  }

  /// One revision to switch to.
  public struct Choice: Equatable, Sendable, Identifiable {
    public let draft: DraftID
    /// "Revision 19".
    public let label: String
    /// "12 September 2021", when Datatracker dates it.
    public let date: String?
    public let isShown: Bool
    public var id: String { draft.description }
  }

  /// Every revision, newest first; only the one on screen before Datatracker has
  /// said what there is.
  public var choices: [Choice] {
    let revisions = info?.revisions ?? []
    guard !revisions.isEmpty else {
      return shown.revision.map {
        [
          Choice(
            draft: shown, label: Self.revisionLabel($0, locale: locale), date: nil, isShown: true)
        ]
      } ?? []
    }
    var style = Date.FormatStyle.dateTime.day().month(.wide).year()
    style.locale = locale
    return revisions.reversed().compactMap { revision in
      guard let draft = shown.at(revision: revision.revision) else { return nil }
      return Choice(
        draft: draft, label: Self.revisionLabel(revision.revision, locale: locale),
        date: revision.published?.formatted(style), isShown: draft == shown)
    }
  }

  private static func revisionLabel(_ revision: String, locale: Locale) -> String {
    String(kit: "Revision \(number(revision))", locale: locale)
  }

  /// `19` of `19`, and `0` of `00`: a revision as a number is spoken, its digits
  /// are the archive's.
  private static func number(_ revision: String) -> Int {
    Int(revision) ?? 0
  }
}
