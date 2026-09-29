import Foundation
import RFCKit

/// `revisions-scan.json`: what the revisions scanner has read, one entry per adopted
/// draft read successfully, including drafts that revise nothing, so a daily run reads
/// only what changed. A draft whose read failed keeps its previous entry, or has none:
/// either way the listing no longer matches it, and the next run reads it again.
/// `revisions.json` is a pure function of it. The app never reads it
/// (docs/superpowers/specs/2026-09-29-rfc-revisions-design.md, "The scan record").
public struct RevisionScan: Codable, Sendable, Equatable {
  /// The version of the header reading this build does. Bump it with any change to how
  /// `DraftHeader` reads a draft: a scan by another version is not reused, so the fix
  /// reaches every draft, including those that have not changed on datatracker since.
  public static let readerVersion = 1

  /// The `readerVersion` that read `drafts`.
  public var reader: Int
  public var drafts: [String: Entry]

  public init(drafts: [String: Entry]) {
    self.reader = Self.readerVersion
    self.drafts = drafts
  }

  /// `previous`, when this build's reader made it; nil otherwise, which reads every
  /// draft in full as a first run does.
  public static func reusable(_ previous: RevisionScan?) -> RevisionScan? {
    previous?.reader == readerVersion ? previous : nil
  }

  public struct Entry: Codable, Sendable, Equatable {
    /// The states the listing had when `reading` was read. Kept as they were when a
    /// later read fails, so the next run sees them change and reads the record again.
    public var stateIDs: [Int]
    /// From today's listing, whether or not the draft was read.
    public var stage: RevisionStage
    public var stream: String
    public var reading: Reading

    public init(stateIDs: [Int], stage: RevisionStage, stream: String, reading: Reading) {
      self.stateIDs = stateIDs
      self.stage = stage
      self.stream = stream
      self.reading = reading
    }
  }

  public enum ReadingError: Error, Equatable {
    /// The record has no posting of the revision that was read.
    case noSuchRevision(String)
  }

  /// What a draft's header and its record said, at `rev`.
  public struct Reading: Codable, Sendable, Equatable {
    public var rev: String
    public var obsoletes: [Int]
    public var updates: [Int]
    public var published: Date
    public var group: String?
    public var intendedStatus: String?

    public init(
      rev: String, obsoletes: [Int], updates: [Int], published: Date, group: String?,
      intendedStatus: String?
    ) {
      self.rev = rev
      self.obsoletes = obsoletes
      self.updates = updates
      self.published = published
      self.group = group
      self.intendedStatus = intendedStatus
    }

    public init(rev: String, header: DraftHeader, record: Datatracker.DraftRecord) throws {
      guard let published = record.published(rev: rev) else {
        throw ReadingError.noSuchRevision(rev)
      }
      self.init(
        rev: rev, obsoletes: header.obsoletes, updates: header.updates, published: published,
        group: record.groupAcronym, intendedStatus: record.intendedStdLevel)
    }

    /// The same header, with what a newer record says about the group and status.
    public func refreshed(with record: Datatracker.DraftRecord) throws -> Reading {
      try Reading(
        rev: rev, header: DraftHeader(obsoletes: obsoletes, updates: updates), record: record)
    }
  }

  public enum Work: Equatable, Sendable {
    /// Nothing changed.
    case none
    /// The states changed: read `doc.json` again.
    case record
    /// New, or a new revision: read the header and `doc.json`.
    case full
  }

  public static func work(for draft: Datatracker.ListedDraft, previous: Entry?) -> Work {
    guard let previous, previous.reading.rev == draft.rev else { return .full }
    return previous.stateIDs == draft.stateIDs ? .none : .record
  }

  /// The next record, from this run's adopted drafts and what it read. A draft in
  /// `readings` was read; any other keeps its entry, whether it was not due or its
  /// read failed, with its stage taken from today's listing. A draft no longer listed
  /// is left out: it expired, was replaced, or was published.
  public static func next(
    adopted: [Datatracker.ListedDraft], states: [Int: DraftState], previous: RevisionScan?,
    readings: [String: Reading]
  ) -> RevisionScan {
    var drafts: [String: Entry] = [:]
    for draft in adopted {
      let stage = DraftStates.stage(draft.states(in: states))
      let stream = draft.streamSlug ?? "ietf"
      if let reading = readings[draft.name] {
        drafts[draft.name] = Entry(
          stateIDs: draft.stateIDs, stage: stage, stream: stream, reading: reading)
      } else if var kept = previous?.drafts[draft.name] {
        kept.stage = stage
        kept.stream = stream
        drafts[draft.name] = kept
      }
    }
    return RevisionScan(drafts: drafts)
  }

  /// `revisions.json`: every relation of every draft read successfully, under its RFC,
  /// in draft-name order so two runs write the same bytes.
  public func revisions(generatedAt: Date) -> RFCRevisions {
    var byRFC: [Int: [RFCRevisions.Revision]] = [:]
    for name in drafts.keys.sorted() {
      guard let entry = drafts[name] else { continue }
      let reading = entry.reading
      let relations: [(RevisionRelation, [Int])] = [
        (.obsoletes, reading.obsoletes), (.updates, reading.updates),
      ]
      for (relation, numbers) in relations {
        for number in Set(numbers).sorted() {
          byRFC[number, default: []].append(
            RFCRevisions.Revision(
              relation: relation, draft: name, revision: reading.rev,
              published: reading.published, stream: entry.stream, group: reading.group,
              intendedStatus: reading.intendedStatus, stage: entry.stage))
        }
      }
    }
    return RFCRevisions(generatedAt: generatedAt, revisions: byRFC)
  }

  /// False when `next` has lost more than half the RFCs of a `previous` that had at
  /// least ten: a real change in the drafts does not do that, a broken query does.
  public static func mayPublish(
    _ next: RFCRevisions, replacing previous: RFCRevisions?, allowShrink: Bool
  ) -> Bool {
    guard let previous, !allowShrink, previous.revisions.count >= 10 else { return true }
    return next.revisions.count * 2 >= previous.revisions.count
  }

  /// In the coders of `revisions.json`, which it sits beside on the release.
  public static func decode(_ data: Data) throws -> RevisionScan {
    try RFCRevisions.decoder().decode(RevisionScan.self, from: data)
  }

  public func encoded() throws -> Data {
    try RFCRevisions.encoder().encode(self)
  }
}
