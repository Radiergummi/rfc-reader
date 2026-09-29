import Foundation
import RFCKit

/// What a document's menus hold: Cite, More and Add to Collection.
///
/// Both platforms show them — iOS as SwiftUI menus in the reader's toolbar, macOS
/// as `NSMenu`s on the window's toolbar items — and each wrote its own copy, which
/// had to agree item for item. This is the one list; each renderer walks it and
/// does the actions its own way.
public enum DocumentMenus {
  public enum Action: Hashable, Sendable {
    case copyCitation(CitationStyle)
    case copySectionLink
    case toggleOriginalText
    case openInfoPage
    case openErrata(URL)
    case openDatatracker
    case openPrecedingDraft(URL)
    /// Adds the document to the collection, or takes it out.
    case toggleCollection(UUID)
    case newCollection
  }

  /// An item's symbol, and the color it is drawn in where it has one of its own —
  /// a collection's, as the sidebar draws it — rather than the menu's.
  ///
  /// Only an item that names a thing has one: macOS 27 hides menu icons unless an
  /// item asks for its own, and keeps them for items that name an object rather
  /// than an action, so every icon here is one a renderer shows.
  public struct Icon: Hashable, Sendable {
    public let symbol: String
    public let color: CollectionColor?

    public init(_ symbol: String, color: CollectionColor? = nil) {
      self.symbol = symbol
      self.color = color
    }
  }

  public struct Item: Hashable, Sendable {
    public let title: String
    public let action: Action
    /// On or off for an item that is a toggle, nil for one that is not.
    public let isOn: Bool?
    public let icon: Icon?

    public init(_ title: String, _ action: Action, isOn: Bool? = nil, icon: Icon? = nil) {
      self.title = title
      self.action = action
      self.isOn = isOn
      self.icon = icon
    }
  }

  /// A menu's items in sections, which a renderer separates.
  public typealias Sections = [[Item]]

  /// Every citation style, then the link to where the reader is.
  public static func cite() -> Sections {
    [
      CitationStyle.allCases.map { Item($0.displayName, .copyCitation($0)) },
      [Item("Copy Link to Current Section", .copySectionLink)],
    ]
  }

  /// What is used least: the original text, and the document's pages elsewhere —
  /// errata and the preceding draft only where the document has them.
  public static func more(showsOriginal: Bool, errata: URL?, precedingDraft: URL?) -> Sections {
    var pages = [Item("Open on rfc-editor.org", .openInfoPage)]
    if let errata { pages.append(Item("Errata", .openErrata(errata))) }
    pages.append(Item("Datatracker", .openDatatracker))
    if let precedingDraft {
      pages.append(Item("Preceding Draft", .openPrecedingDraft(precedingDraft)))
    }
    return [[Item("Original Text", .toggleOriginalText, isOn: showsOriginal)], pages]
  }

  /// Every collection, checked where `document` is already in it, and New
  /// Collection (#349) — after a separator only when there are collections above it.
  public static func addToCollection(
    _ document: DocumentID, in snapshot: CollectionSnapshot
  ) -> Sections {
    let containing = snapshot.collections(containing: document)
    let collections = snapshot.collections.map {
      Item(
        $0.name, .toggleCollection($0.id), isOn: containing.contains($0.id),
        icon: Icon("folder", color: $0.color))
    }
    let create = [Item("New Collection…", .newCollection)]
    return collections.isEmpty ? [create] : [collections, create]
  }
}
