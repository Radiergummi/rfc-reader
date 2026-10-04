import Foundation
import RFCKit

/// What the reader says about drafts revising one RFC: the banner's rows and the
/// inspector's, in the order and words of
/// docs/superpowers/specs/2026-09-29-rfc-revisions-design.md, "The interface".
public struct RevisionsSummary: Equatable, Sendable {
  /// Furthest stage first, then obsoletes before updates, then by name.
  public let revisions: [RFCRevisions.Revision]
  /// "17 September", the file's date, when it is more than three days old and every
  /// stage says "as of" it; with the year when that is not this one.
  private let asOf: String?
  private let now: Date
  private let locale: Locale
  private let timeZone: TimeZone

  public struct Line: Equatable, Sendable, Identifiable {
    /// "Being replaced by".
    public let relation: String
    /// "draft-ietf-httpbis-rfc6265bis-22".
    public let title: String
    /// The draft's datatracker page.
    public let url: URL
    public let detail: String
    /// One sentence, "Being replaced by draft-…, revision 22, in the RFC Editor queue".
    public let accessibilityLabel: String
    public var id: String { relation + title }
  }

  private static let staleAfter: TimeInterval = 3 * 86_400
  private static let dormantAfter: TimeInterval = 365 * 86_400
  private static let bannerLimit = 2

  /// - Parameter document: only an RFC has revisions, as the file is keyed by RFC
  ///   number: BCP 14 is not RFC 14.
  public init(
    _ file: RFCRevisions?, for document: DocumentID, now: Date, locale: Locale = .interface,
    timeZone: TimeZone = .current
  ) {
    let listed = document.series == .rfc ? file?.revisions[document.number] : nil
    revisions = (listed ?? []).sorted { lhs, rhs in
      if lhs.stage != rhs.stage { return lhs.stage > rhs.stage }
      if lhs.relation != rhs.relation { return lhs.relation == .obsoletes }
      return lhs.draft < rhs.draft
    }
    if let file, now.timeIntervalSince(file.generatedAt) > Self.staleAfter {
      // The year only when it is not this one: "17 September", "17 August 2025".
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = timeZone
      let style: Date.FormatStyle =
        calendar.component(.year, from: file.generatedAt) == calendar.component(.year, from: now)
        ? .dateTime.day().month(.wide) : .dateTime.day().month(.wide).year()
      asOf = Self.format(file.generatedAt, style, locale: locale, timeZone: timeZone)
    } else {
      asOf = nil
    }
    self.now = now
    self.locale = locale
    self.timeZone = timeZone
  }

  public var isEmpty: Bool { revisions.isEmpty }

  /// The file is more than three days old.
  public var isStale: Bool { asOf != nil }

  public var bannerLines: [Line] {
    revisions.prefix(Self.bannerLimit).map { line($0, inFull: false) }
  }

  /// "and 2 more", past the banner's two rows; the inspector lists them all.
  public var moreText: String? {
    revisions.count > Self.bannerLimit
      ? String(kit: "and \(revisions.count - Self.bannerLimit) more", locale: locale) : nil
  }

  /// Every draft of one relation, in full, for the inspector.
  public func inspectorLines(_ relation: RevisionRelation) -> [Line] {
    revisions.filter { $0.relation == relation }.map { line($0, inFull: true) }
  }

  public static func relationLabel(
    _ relation: RevisionRelation, locale: Locale = .interface
  ) -> String {
    switch relation {
    case .obsoletes: String(kit: "Being replaced by", locale: locale)
    case .updates: String(kit: "Being updated by", locale: locale)
    }
  }

  public static func stageName(
    _ stage: RevisionStage, stream: String, locale: Locale = .interface
  ) -> String {
    switch stage {
    case .rfcEditorQueue: String(kit: "In the RFC Editor queue", locale: locale)
    case .approved: String(kit: "Approved for publication", locale: locale)
    case .iesgReview: String(kit: "Under IESG review", locale: locale)
    case .ietfLastCall: String(kit: "In IETF Last Call", locale: locale)
    case .submitted: String(kit: "Submitted for publication", locale: locale)
    case .lastCall: String(kit: "In working group last call", locale: locale)
    // The Independent stream has no group to be in.
    case .inGroup:
      if stream == "ise" {
        String(kit: "Under review", locale: locale)
      } else {
        String(kit: "In the working group", locale: locale)
      }
    }
  }

  /// The stage in the middle of a sentence: words of its own, not `stageName` with
  /// its first letter lowered, which would lower a German noun.
  public static func stagePhrase(
    _ stage: RevisionStage, stream: String, locale: Locale = .interface
  ) -> String {
    switch stage {
    case .rfcEditorQueue: String(kit: "in the RFC Editor queue", locale: locale)
    case .approved: String(kit: "approved for publication", locale: locale)
    case .iesgReview: String(kit: "under IESG review", locale: locale)
    case .ietfLastCall: String(kit: "in IETF Last Call", locale: locale)
    case .submitted: String(kit: "submitted for publication", locale: locale)
    case .lastCall: String(kit: "in working group last call", locale: locale)
    case .inGroup:
      if stream == "ise" {
        String(kit: "under review", locale: locale)
      } else {
        String(kit: "in the working group", locale: locale)
      }
    }
  }

  /// A draft's line. Its detail is the stage for the banner, where a dormant draft
  /// also dates its revision, and everything known for the inspector (`inFull`).
  private func line(_ revision: RFCRevisions.Revision, inFull: Bool) -> Line {
    let relation = Self.relationLabel(revision.relation, locale: locale)
    let stage = Self.stageName(revision.stage, stream: revision.stream, locale: locale)
    let dormant = dormantMonth(revision)

    let detail: String
    if inFull {
      var parts = [format(revision.published, .dateTime.day().month(.wide).year())]
      if let group = revision.group { parts.append(group.uppercased()) }
      if let status = revision.intendedStatus {
        parts.append(String(kit: "intended \(status)", locale: locale))
      }
      parts.append(asOf(stage))
      detail = parts.joined(separator: " · ")
    } else {
      detail = asOf(
        dormant.map { String(kit: "\(stage), revision of \($0)", locale: locale) } ?? stage)
    }

    let number = Int(revision.revision).map(String.init) ?? revision.revision
    let phrase = Self.stagePhrase(revision.stage, stream: revision.stream, locale: locale)
    let sentence =
      if let dormant {
        String(
          kit: "\(relation) \(revision.draft), revision \(number) from \(dormant), \(phrase)",
          locale: locale)
      } else {
        String(kit: "\(relation) \(revision.draft), revision \(number), \(phrase)", locale: locale)
      }
    return Line(
      relation: relation, title: "\(revision.draft)-\(revision.revision)",
      url: RFCEditorEndpoints.datatrackerDraft(revision.draft), detail: detail,
      accessibilityLabel: asOf(sentence))
  }

  /// `text`, dated by the file when it is stale: "In the RFC Editor queue, as of 17
  /// September".
  private func asOf(_ text: String) -> String {
    asOf.map { String(kit: "\(text), as of \($0)", locale: locale) } ?? text
  }

  /// "May 2014", when the revision is more than a year old.
  private func dormantMonth(_ revision: RFCRevisions.Revision) -> String? {
    guard now.timeIntervalSince(revision.published) > Self.dormantAfter else { return nil }
    return format(revision.published, .dateTime.month(.wide).year())
  }

  private func format(_ date: Date, _ style: Date.FormatStyle) -> String {
    Self.format(date, style, locale: locale, timeZone: timeZone)
  }

  private static func format(
    _ date: Date, _ style: Date.FormatStyle, locale: Locale, timeZone: TimeZone
  ) -> String {
    var style = style
    style.locale = locale
    style.timeZone = timeZone
    return date.formatted(style)
  }
}
