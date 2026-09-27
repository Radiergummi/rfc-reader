import Foundation
import RFCKit

/// What the list in the middle column shows.
public enum LibraryFilter: Hashable, Identifiable, Sendable {
  case all
  case recent
  case bookmarks
  case downloaded
  case standards
  case bestCurrentPractice
  case stream(RFCKit.Stream)
  case workingGroup(String)
  case series(DocumentID)

  public var id: Self { self }

  public var title: String {
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
    }
  }

  /// The collection a script names, by the title the sidebar shows for it — the
  /// same string a script reads back — without regard to case: "All RFCs",
  /// "bookmarks", "IETF", "BCP 14", "httpbis".
  ///
  /// A working group is only one the index knows, and comes back spelled the way
  /// the index spells it, because that is the string the list compares its rows'
  /// groups against. Nil for anything else, which a script hears as an error
  /// rather than as a collection that quietly lists nothing.
  public init?(scriptName: String, workingGroups: Set<String>) {
    let name = scriptName.trimmingCharacters(in: .whitespacesAndNewlines)
    let fixed: [LibraryFilter] = [
      .all, .recent, .bookmarks, .downloaded, .standards, .bestCurrentPractice,
    ]
    let streams = RFCKit.Stream.allCases.map(LibraryFilter.stream)
    if let match = (fixed + streams).first(where: {
      $0.title.caseInsensitiveCompare(name) == .orderedSame
    }) {
      self = match
    } else if let id = DocumentID(parsing: name), id.series != .rfc {
      self = .series(id)
    } else if let group = workingGroups.first(where: {
      $0.caseInsensitiveCompare(name) == .orderedSame
    }) {
      self = .workingGroup(group)
    } else {
      return nil
    }
  }
}
