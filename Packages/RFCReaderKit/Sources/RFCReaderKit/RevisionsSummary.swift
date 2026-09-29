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

  public init(
    _ file: RFCRevisions?, rfc number: Int, now: Date, locale: Locale = .current,
    timeZone: TimeZone = .current
  ) {
    revisions = (file?.revisions[number] ?? []).sorted { lhs, rhs in
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
    revisions.count > Self.bannerLimit ? "and \(revisions.count - Self.bannerLimit) more" : nil
  }

  /// Every draft of one relation, in full, for the inspector.
  public func inspectorLines(_ relation: RevisionRelation) -> [Line] {
    revisions.filter { $0.relation == relation }.map { line($0, inFull: true) }
  }

  public static func relationLabel(_ relation: RevisionRelation) -> String {
    switch relation {
    case .obsoletes: "Being replaced by"
    case .updates: "Being updated by"
    }
  }

  public static func stageName(_ stage: RevisionStage, stream: String) -> String {
    switch stage {
    case .rfcEditorQueue: "In the RFC Editor queue"
    case .approved: "Approved for publication"
    case .iesgReview: "Under IESG review"
    case .ietfLastCall: "In IETF Last Call"
    case .submitted: "Submitted for publication"
    case .lastCall: "In working group last call"
    // The Independent stream has no group to be in.
    case .inGroup: stream == "ise" ? "Under review" : "In the working group"
    }
  }

  /// A draft's line. Its detail is the stage for the banner, where a dormant draft
  /// also dates its revision, and everything known for the inspector (`inFull`).
  private func line(_ revision: RFCRevisions.Revision, inFull: Bool) -> Line {
    let relation = Self.relationLabel(revision.relation)
    let stage = Self.stageName(revision.stage, stream: revision.stream)
    let dormant = dormantMonth(revision)
    let asOfSuffix = asOf.map { ", as of \($0)" } ?? ""

    let detail: String
    if inFull {
      var parts = [format(revision.published, .dateTime.day().month(.wide).year())]
      if let group = revision.group { parts.append(group.uppercased()) }
      if let status = revision.intendedStatus { parts.append("intended \(status)") }
      parts.append(stage + asOfSuffix)
      detail = parts.joined(separator: " · ")
    } else {
      detail = stage + (dormant.map { ", revision of \($0)" } ?? "") + asOfSuffix
    }

    let number = Int(revision.revision).map(String.init) ?? revision.revision
    var sentence = "\(relation) \(revision.draft), revision \(number)"
    if let dormant { sentence += " from \(dormant)" }
    sentence += ", " + Self.lowercasingFirst(stage) + asOfSuffix
    return Line(
      relation: relation, title: "\(revision.draft)-\(revision.revision)",
      url: RFCEditorEndpoints.datatrackerDraft(revision.draft), detail: detail,
      accessibilityLabel: sentence)
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

  /// "In the RFC Editor queue" → "in the RFC Editor queue", for the middle of a sentence.
  private static func lowercasingFirst(_ string: String) -> String {
    string.prefix(1).lowercased() + string.dropFirst()
  }
}
