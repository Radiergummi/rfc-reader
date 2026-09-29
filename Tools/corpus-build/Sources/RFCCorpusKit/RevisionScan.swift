import Foundation
import RFCKit

/// `revisions-scan.json`: what the revisions scanner has read, one entry per adopted
/// draft, including drafts that revise nothing, so a daily run reads only what
/// changed. `revisions.json` is a pure function of it. The app never reads it
/// (docs/superpowers/specs/2026-09-29-rfc-revisions-design.md, "The scan record").
public struct RevisionScan: Codable, Sendable, Equatable {
  public var drafts: [String: Entry]

  public init(drafts: [String: Entry]) {
    self.drafts = drafts
  }

  public struct Entry: Codable, Sendable, Equatable {
    /// The revision the listing had when this entry was written.
    public var rev: String
    public var stateIDs: [Int]
    public var stage: RevisionStage
    public var stream: String
    /// Nil until a read has succeeded.
    public var reading: Reading?
    /// The last read failed; the next run reads the draft again in full.
    public var failed: Bool

    public init(
      rev: String, stateIDs: [Int], stage: RevisionStage, stream: String, reading: Reading?,
      failed: Bool
    ) {
      self.rev = rev
      self.stateIDs = stateIDs
      self.stage = stage
      self.stream = stream
      self.reading = reading
      self.failed = failed
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
        group: record.groupAcronym, intendedStatus: record.intendedStatus)
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
    /// New, a new revision, or the last read failed: read the header and `doc.json`.
    case full
  }

  public static func work(for draft: Datatracker.ListedDraft, previous: Entry?) -> Work {
    guard let previous, previous.reading != nil, !previous.failed, previous.rev == draft.rev
    else { return .full }
    return previous.stateIDs == draft.stateIDs ? .none : .record
  }

  /// The next record, from this run's adopted drafts and what it read. A draft in
  /// `readings` was read; one in `failures` failed; any other was not due and keeps its
  /// entry. A draft no longer listed is left out: it expired, was replaced, or was
  /// published.
  public static func next(
    adopted: [Datatracker.ListedDraft], states: [Int: DraftState], previous: RevisionScan?,
    readings: [String: Reading], failures: Set<String>
  ) -> RevisionScan {
    var drafts: [String: Entry] = [:]
    for draft in adopted {
      let stage = DraftStates.stage(draft.states(in: states))
      let stream = draft.streamSlug ?? "ietf"
      let old = previous?.drafts[draft.name]
      if let reading = readings[draft.name] {
        drafts[draft.name] = Entry(
          rev: draft.rev, stateIDs: draft.stateIDs, stage: stage, stream: stream,
          reading: reading, failed: false)
      } else if failures.contains(draft.name) {
        var kept =
          old
          ?? Entry(
            rev: draft.rev, stateIDs: draft.stateIDs, stage: stage, stream: stream,
            reading: nil, failed: true)
        kept.failed = true
        drafts[draft.name] = kept
      } else if var kept = old {
        kept.stateIDs = draft.stateIDs
        kept.stage = stage
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
      guard let entry = drafts[name], let reading = entry.reading else { continue }
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

  public static func decode(_ data: Data) throws -> RevisionScan {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(RevisionScan.self, from: data)
  }

  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(self)
  }
}
