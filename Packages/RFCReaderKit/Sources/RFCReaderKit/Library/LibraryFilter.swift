import Foundation
import RFCKit

/// What the list in the middle column shows.
public enum LibraryFilter: Hashable, Identifiable, Sendable, Codable {
  case all
  case recent
  case bookmarks
  case downloaded
  case standards
  case bestCurrentPractice
  case stream(PublicationStream)
  case workingGroup(String)
  case series(DocumentID)
  /// A collection the reader made (#349). Its name is the collection's and not the
  /// filter's to carry: `title(in:)` reads it from the snapshot.
  case collection(UUID)

  public var id: Self { self }

  /// What the sidebar, the list and scripts call this filter. A collection is
  /// called by its name in `collections`, and one that has gone since by nothing.
  public func title(in collections: CollectionSnapshot) -> String {
    switch self {
    case .all: "All RFCs"
    case .recent: "Recently Read"
    case .bookmarks: "Bookmarks"
    case .downloaded: "Available Offline"
    case .standards: "Internet Standards"
    case .bestCurrentPractice: "Best Current Practices"
    case .stream(let stream): stream.displayName
    case .workingGroup(let group): group.uppercased()
    case .series(let id): id.displayName
    case .collection(let identifier): collections[identifier]?.name ?? ""
    }
  }

  public var systemImage: String {
    switch self {
    case .all: "books.vertical"
    case .recent: "clock"
    case .bookmarks: "bookmark"
    case .downloaded: "arrow.down.circle"
    case .standards: "checkmark.seal"
    case .bestCurrentPractice: "hand.thumbsup"
    case .stream: "tray"
    case .workingGroup: "person.2"
    case .series: "square.stack"
    case .collection: "folder"
    }
  }

  /// Whether `rfc` is in this filter's list, for the filters the index alone
  /// decides: nil for those the reader's own data decides, and for a series, whose
  /// members the index lists rather than marks.
  ///
  /// One predicate for the list and for the sidebar's count of it, so the two
  /// cannot disagree.
  public func includes(_ rfc: RFCMetadata) -> Bool? {
    switch self {
    case .all: true
    case .standards: rfc.currentStatus == .internetStandard
    case .bestCurrentPractice: rfc.currentStatus == .bestCurrentPractice
    case .stream(let stream): rfc.stream == stream
    case .workingGroup(let group): rfc.workingGroup == group
    case .recent, .bookmarks, .downloaded, .series, .collection: nil
    }
  }

  /// Whether every RFC this filter lists has the same status, which its rows then
  /// need not each show.
  public var fixesStatus: Bool {
    switch self {
    case .standards, .bestCurrentPractice: true
    default: false
    }
  }

  /// Whether every RFC this filter lists is from the same working group, which its
  /// rows then need not each show: PPPEXT's rows need not each say "pppext".
  public var fixesWorkingGroup: Bool {
    if case .workingGroup = self { return true }
    return false
  }

  /// The collection a script names, by the title the sidebar shows for it — the
  /// same string a script reads back — without regard to case: "All RFCs",
  /// "bookmarks", "IETF", "BCP 14", "httpbis".
  ///
  /// A working group is only one the index knows, and comes back spelled the way
  /// the index spells it, because that is the string the list compares its rows'
  /// groups against. Nil for anything else, which a script hears as an error
  /// rather than as a collection that quietly lists nothing.
  ///
  /// Then a collection the reader made (#349), the first in sidebar order among any
  /// of one name. A built-in name, a series or a working group wins a clash, so no
  /// script changes meaning because a collection took its name.
  public init?(
    scriptName: String, workingGroups: Set<String>, collections: [CollectionSnapshot.Entry] = []
  ) {
    let name = scriptName.trimmingCharacters(in: .whitespacesAndNewlines)
    let fixed: [LibraryFilter] = [
      .all, .recent, .bookmarks, .downloaded, .standards, .bestCurrentPractice,
    ]
    let streams = PublicationStream.allCases.map(LibraryFilter.stream)
    if let match = (fixed + streams).first(where: {
      $0.title(in: .empty).caseInsensitiveCompare(name) == .orderedSame
    }) {
      self = match
    } else if let id = DocumentID(parsing: name), id.series != .rfc {
      self = .series(id)
    } else if let group = workingGroups.first(where: {
      $0.caseInsensitiveCompare(name) == .orderedSame
    }) {
      self = .workingGroup(group)
    } else if let collection = collections.first(where: {
      $0.name.caseInsensitiveCompare(name) == .orderedSame
    }) {
      self = .collection(collection.id)
    } else {
      return nil
    }
  }
}
