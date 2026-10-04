import Foundation
import RFCKit

/// What the bookmarked RFCs looked like at the last comparison (#191): what the index
/// says of each, and which drafts revise it at which stage. The next comparison reports
/// what changed since.
///
/// Kept per device and never synced, so a new device starts from what it first sees
/// rather than reporting history, and both a Mac and an iPhone tell their own reader.
///
/// A section is nil when its data was not there to read. An RFC is compared in a
/// section only when both baselines have an entry for it, which they have only while it
/// is bookmarked: a newly bookmarked RFC reports nothing from before.
public struct BookmarkBaseline: Codable, Sendable, Equatable {
  /// What the index says of a bookmarked document: its entry's obsoleted-by,
  /// updated-by and errata. A document the index does not list has no entry.
  public var index: [DocumentID: IndexRecord]?
  /// Each bookmarked RFC's revising drafts, by name; empty when none is listed. A
  /// draft the file stops listing is kept at the stage it was last seen at, so one
  /// that drops out of a day's file and comes back is not reported again.
  public var revisions: [DocumentID: [String: RevisionRecord]]?

  public struct IndexRecord: Codable, Sendable, Equatable {
    public var obsoletedBy: Set<DocumentID>
    public var updatedBy: Set<DocumentID>
    public var hasErrata: Bool
  }

  public struct RevisionRecord: Codable, Sendable, Equatable {
    public var relation: RevisionRelation
    public var stage: RevisionStage
    /// "ietf" or "ise", which words the earliest stage.
    public var stream: String
  }

  /// The baseline of `bookmarks` now. A section whose data is missing keeps what
  /// `previous` had of it, for the RFCs still bookmarked, so a launch that has no
  /// index yet neither reports nor forgets anything.
  public init(
    bookmarks: Set<DocumentID>, index: RFCIndex?, revisions: RFCRevisions?,
    carryingOver previous: BookmarkBaseline?
  ) {
    if let index {
      var records: [DocumentID: IndexRecord] = [:]
      for document in bookmarks {
        guard let entry = index[document] else { continue }
        records[document] = IndexRecord(
          obsoletedBy: Set(entry.obsoletedBy), updatedBy: Set(entry.updatedBy),
          hasErrata: entry.hasErrata)
      }
      self.index = records
    } else {
      self.index = previous?.index?.filter { bookmarks.contains($0.key) }
    }
    if let revisions {
      var records: [DocumentID: [String: RevisionRecord]] = [:]
      // Only an RFC: the file is keyed by RFC number, and BCP 14 is not RFC 14.
      for document in bookmarks where document.series == .rfc {
        var drafts = previous?.revisions?[document] ?? [:]
        for revision in revisions.revisions[document.number] ?? [] {
          drafts[revision.draft] = RevisionRecord(
            relation: revision.relation, stage: revision.stage, stream: revision.stream)
        }
        records[document] = drafts
      }
      self.revisions = records
    } else {
      self.revisions = previous?.revisions?.filter { bookmarks.contains($0.key) }
    }
  }

  public static func decode(_ data: Data) throws -> BookmarkBaseline {
    try JSONDecoder().decode(BookmarkBaseline.self, from: data)
  }

  public func encoded() throws -> Data {
    try JSONEncoder().encode(self)
  }
}

/// One change to a bookmarked RFC, worth telling its reader about.
public enum BookmarkEvent: Hashable, Sendable {
  case obsoleted(DocumentID, newer: [DocumentID])
  case updated(DocumentID, newer: [DocumentID])
  /// A draft now intends to obsolete or update the RFC.
  case revisionStarted(
    DocumentID, draft: String, relation: RevisionRelation, stage: RevisionStage, stream: String)
  /// A draft already listed reached the RFC Editor queue: publication is near.
  case revisionQueued(DocumentID, draft: String, relation: RevisionRelation)
  /// The index lists errata for the RFC where it listed none. It does not say whether
  /// they are verified, which needs the errata data #387 builds.
  case errataListed(DocumentID)

  public var document: DocumentID {
    switch self {
    case .obsoleted(let document, _), .updated(let document, _),
      .revisionStarted(let document, _, _, _, _), .revisionQueued(let document, _, _),
      .errataListed(let document):
      document
    }
  }
}

public enum BookmarkEvents {
  /// What changed from `old` to `new`, by document, and for each: obsoleted, updated,
  /// its drafts by name, errata. Nothing when there is no `old`: a first comparison
  /// only sets the baseline.
  public static func between(_ old: BookmarkBaseline?, _ new: BookmarkBaseline) -> [BookmarkEvent] {
    guard let old else { return [] }
    var events: [BookmarkEvent] = []
    let documents = Set((new.index ?? [:]).keys).union((new.revisions ?? [:]).keys).sorted()
    for document in documents {
      if let before = old.index?[document], let after = new.index?[document] {
        let obsoleting = after.obsoletedBy.subtracting(before.obsoletedBy).sorted()
        if !obsoleting.isEmpty { events.append(.obsoleted(document, newer: obsoleting)) }
        let updating = after.updatedBy.subtracting(before.updatedBy).sorted()
        if !updating.isEmpty { events.append(.updated(document, newer: updating)) }
      }
      if let before = old.revisions?[document], let after = new.revisions?[document] {
        for (draft, revision) in after.sorted(by: { $0.key < $1.key }) {
          if let earlier = before[draft] {
            if earlier.stage < .rfcEditorQueue, revision.stage == .rfcEditorQueue {
              events.append(.revisionQueued(document, draft: draft, relation: revision.relation))
            }
          } else {
            events.append(
              .revisionStarted(
                document, draft: draft, relation: revision.relation, stage: revision.stage,
                stream: revision.stream))
          }
        }
      }
      if let before = old.index?[document], let after = new.index?[document],
        !before.hasErrata, after.hasErrata
      {
        events.append(.errataListed(document))
      }
    }
    return events
  }
}

/// One notification: every event of one comparison about one RFC, so that a refresh
/// that finds three things about it says so once.
public struct BookmarkNotice: Equatable, Sendable {
  public let document: DocumentID
  /// "RFC 6265".
  public let title: String
  /// The document's title, when the index has it.
  public let subtitle: String?
  /// One line per event: "Obsoleted by RFC 9999."
  public let body: String
  /// The document's `rfc://` link, which a tap on the notification opens.
  public let url: URL

  /// One notice per document, in the order `events` first names them.
  public static func notices(for events: [BookmarkEvent], index: RFCIndex?) -> [BookmarkNotice] {
    var order: [DocumentID] = []
    var lines: [DocumentID: [String]] = [:]
    for event in events {
      if lines[event.document] == nil { order.append(event.document) }
      lines[event.document, default: []].append(line(event))
    }
    return order.map { document in
      BookmarkNotice(
        document: document, title: document.displayName, subtitle: index?[document]?.title,
        body: lines[document, default: []].joined(separator: "\n"),
        url: RFCLink(id: document).appURL)
    }
  }

  private static func line(_ event: BookmarkEvent) -> String {
    switch event {
    case .obsoleted(_, let documents):
      "Obsoleted by \(list(documents))."
    case .updated(_, let documents):
      "Updated by \(list(documents))."
    case .revisionStarted(_, let draft, let relation, let stage, let stream):
      "\(RevisionsSummary.relationLabel(relation)) \(draft), "
        + RevisionsSummary.stagePhrase(stage, stream: stream)
        + "."
    case .revisionQueued(_, let draft, let relation):
      "\(RevisionsSummary.relationLabel(relation)) \(draft), in the RFC Editor queue."
    case .errataListed:
      "Now has errata."
    }
  }

  /// "RFC 9997", "RFC 9997 and RFC 9998", "RFC 9996, RFC 9997 and RFC 9998".
  private static func list(_ documents: [DocumentID]) -> String {
    let names = documents.map(\.displayName)
    guard let last = names.last, names.count > 1 else { return names.first ?? "" }
    return names.dropLast().joined(separator: ", ") + " and " + last
  }
}
