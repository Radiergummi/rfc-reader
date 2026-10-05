import Foundation
import RFCKit

/// What a document's menus hold: Cite, More and Add to Collection.
///
/// Both platforms show them — iOS as SwiftUI menus in the reader's toolbar, macOS
/// as `NSMenu`s on the window's toolbar items — and each wrote its own copy, which
/// had to agree item for item. This is the one list; each renderer walks it, and
/// what an item of Cite or More does is `Action.effect`, which each platform
/// carries out (#600).
public enum DocumentMenus {
  /// What an item of Cite or More does.
  public enum Action: Hashable, Sendable {
    case copyCitation(CitationStyle)
    case copySectionLink
    case toggleOriginalText
    case openInfoPage
    case openErrata(URL)
    case openDatatracker
    case openPrecedingDraft(URL)
  }

  /// What an item of Add to Collection does: a menu of its own, offered from the
  /// list's rows and the menu bar as well as the reader (#349).
  public enum CollectionAction: Hashable, Sendable {
    /// Adds the document to the collection, or takes it out.
    case toggleCollection(UUID)
    case newCollection
  }

  /// What an `Action` comes to, on either platform.
  public enum Effect: Equatable, Sendable {
    /// The text, and what it is, which the copy announces.
    case copy(String, CopyFeedback)
    case open(URL)
    case toggleOriginalText
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

  public struct Item<Performed: Hashable & Sendable>: Hashable, Sendable {
    public let title: String
    public let action: Performed
    /// On or off for an item that is a toggle, nil for one that is not.
    public let isOn: Bool?
    public let icon: Icon?

    public init(_ title: String, _ action: Performed, isOn: Bool? = nil, icon: Icon? = nil) {
      self.title = title
      self.action = action
      self.isOn = isOn
      self.icon = icon
    }
  }

  /// A menu's items in sections, which a renderer separates.
  public typealias Sections<Performed: Hashable & Sendable> = [[Item<Performed>]]

  /// Every citation style, then the link to where the reader is.
  public static func cite(locale: Locale = .interface) -> Sections<Action> {
    [
      CitationStyle.allCases.map { Item($0.title(in: locale), .copyCitation($0)) },
      [Item(String(kit: "Copy Link to Current Section", locale: locale), .copySectionLink)],
    ]
  }

  /// What is used least: the original text, and the document's pages elsewhere —
  /// errata and the preceding draft only where the document has them.
  public static func more(
    showsOriginal: Bool, errata: URL?, precedingDraft: URL?, locale: Locale = .interface
  ) -> Sections<Action> {
    var pages: [Item<Action>] = [
      Item(String(kit: "Open on rfc-editor.org", locale: locale), .openInfoPage)
    ]
    if let errata { pages.append(Item(String(kit: "Errata", locale: locale), .openErrata(errata))) }
    pages.append(Item(String(kit: "Datatracker", locale: locale), .openDatatracker))
    if let precedingDraft {
      pages.append(
        Item(String(kit: "Preceding Draft", locale: locale), .openPrecedingDraft(precedingDraft)))
    }
    let original = Item(
      String(kit: "Original Text", locale: locale), Action.toggleOriginalText, isOn: showsOriginal)
    return [[original], pages]
  }

  /// Every collection, checked where `document` is already in it, and New
  /// Collection (#349) — after a separator only when there are collections above it.
  /// With no document, New Collection alone: there is nothing to add or check.
  public static func addToCollection(
    _ document: DocumentID?, in snapshot: CollectionSnapshot, locale: Locale = .interface
  ) -> Sections<CollectionAction> {
    let create: [Item<CollectionAction>] = [
      Item(String(kit: "New Collection…", locale: locale), .newCollection)
    ]
    guard let document else { return [create] }
    let containing = snapshot.collections(containing: document)
    let collections = snapshot.collections.map { collection -> Item<CollectionAction> in
      Item(
        collection.name, .toggleCollection(collection.id), isOn: containing.contains(collection.id),
        icon: Icon("folder", color: collection.color))
    }
    return collections.isEmpty ? [create] : [collections, create]
  }
}

extension DocumentMenus.Action {
  /// What this does for `id`, read at `section`: nil for a citation without the
  /// document's metadata, which there is nothing to cite from.
  public func effect(
    for id: DocumentID, metadata: RFCMetadata?, section: String?
  ) -> DocumentMenus.Effect? {
    switch self {
    case .copyCitation(let style):
      metadata.map {
        .copy(DocumentActions.citation($0, section: section, style: style), .citation)
      }
    case .copySectionLink: .copy(DocumentActions.sectionLink(id: id, section: section), .link)
    case .toggleOriginalText: .toggleOriginalText
    case .openInfoPage: .open(RFCEditorEndpoints.infoPage(id))
    case .openErrata(let url), .openPrecedingDraft(let url): .open(url)
    case .openDatatracker: .open(RFCEditorEndpoints.datatracker(id))
    }
  }
}
