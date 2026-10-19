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
    /// Shows the document translated into the reader's language, or the original
    /// again (#749).
    case toggleTranslation
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
    case toggleTranslation
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

  /// What is used least: the original text and a translation, and the document's
  /// pages elsewhere — errata and the preceding draft only where the document has
  /// them. A translation is not offered to a reader who reads only English
  /// (`DocumentTranslation.target`).
  public static func more(
    showsOriginal: Bool, showsTranslation: Bool, errata: URL?, precedingDraft: URL?,
    offersTranslation: Bool = DocumentTranslation.target != nil, locale: Locale = .interface
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
    let texts = texts(
      showsOriginal: showsOriginal, showsTranslation: showsTranslation,
      offersTranslation: offersTranslation, locale: locale)
    return [texts, pages]
  }

  /// A draft's More (#728): the original text and a translation, which a draft's
  /// text has as an RFC's does, and none of an RFC's pages, which the RFC Editor
  /// and the index name.
  public static func draftMore(
    showsOriginal: Bool, showsTranslation: Bool,
    offersTranslation: Bool = DocumentTranslation.target != nil, locale: Locale = .interface
  ) -> Sections<Action> {
    [
      texts(
        showsOriginal: showsOriginal, showsTranslation: showsTranslation,
        offersTranslation: offersTranslation, locale: locale)
    ]
  }

  /// Original Text, and Translate where one is offered.
  private static func texts(
    showsOriginal: Bool, showsTranslation: Bool, offersTranslation: Bool, locale: Locale
  ) -> [Item<Action>] {
    let original = Item(
      String(kit: "Original Text", locale: locale), Action.toggleOriginalText, isOn: showsOriginal)
    guard offersTranslation else { return [original] }
    let translation = Item(
      String(kit: "Translate", locale: locale), Action.toggleTranslation, isOn: showsTranslation)
    return [original, translation]
  }

  /// Every collection, checked where `document` is already in it, and New
  /// Collection (#349); not one made from a query, whose members are not chosen
  /// (#355) — after a separator only when there are collections above it.
  /// With no document, New Collection alone: there is nothing to add or check.
  public static func addToCollection(
    _ document: DocumentID?, in snapshot: CollectionSnapshot, locale: Locale = .interface
  ) -> Sections<CollectionAction> {
    let create: [Item<CollectionAction>] = [
      Item(String(kit: "New Collection…", locale: locale), .newCollection)
    ]
    guard let document else { return [create] }
    let containing = snapshot.collections(containing: document)
    let manual = snapshot.collections.filter { !$0.isDynamic }
    let collections = manual.map { collection -> Item<CollectionAction> in
      Item(
        collection.name, .toggleCollection(collection.id), isOn: containing.contains(collection.id),
        icon: Icon("folder", color: collection.color))
    }
    return collections.isEmpty ? [create] : [collections, create]
  }

  /// What a library row's context menu offers, by kind, in order: one table for the
  /// Mac's menu and iOS's (#761), which had drifted apart, each rendering an action
  /// with its own control. The title of each is the renderer's: several are
  /// controls with a state of their own, such as Keep Offline and Add to Collection.
  public enum RowAction: Hashable, Sendable {
    case openInNewTab
    case openInNewWindow
    case bookmark
    case addToCollection
    case readingPath
    case keepOffline
    case share
    case removeFromCollection
  }

  /// What a References panel row that names an RFC offers on a right click or a
  /// long press, by kind, in order (#761): one list for the Mac and iOS.
  public enum ReferenceAction: Hashable, Sendable {
    case openInNewTab
    case openInNewWindow
    case copyLink
    case cite
  }

  /// A reference's menu, where the device opens tabs or windows as given. Cite only
  /// where the index `describes` the document, which a citation is made from: not a
  /// BCP, STD or FYI, nor anything before the index has loaded.
  public static func referenceActions(
    opensTabs: Bool, opensWindows: Bool, describes: Bool = true
  ) -> [[ReferenceAction]] {
    var opening: [ReferenceAction] = []
    if opensTabs { opening.append(.openInNewTab) }
    if opensWindows { opening.append(.openInNewWindow) }
    return [opening, describes ? [.copyLink, .cite] : [.copyLink]].filter { !$0.isEmpty }
  }

  /// The row menu of a row that `isRFC`, or is a BCP, STD or FYI read as itself,
  /// which is bookmarked and opened but neither added to a collection nor shared:
  /// a collection holds RFCs (#321). `opensTabs` and `opensWindows` are what the
  /// device can open it in; `inCollection` is whether the list is a collection's.
  /// Reading Path is offered only with `hasCitationIndex`, without which it can only
  /// say there is none (#769).
  public static func rowActions(
    isRFC: Bool, opensTabs: Bool, opensWindows: Bool, inCollection: Bool,
    hasCitationIndex: Bool
  ) -> [[RowAction]] {
    var opening: [RowAction] = []
    if opensTabs { opening.append(.openInNewTab) }
    if opensWindows { opening.append(.openInNewWindow) }
    var library: [RowAction] = [.bookmark]
    if isRFC {
      library.append(.addToCollection)
      if hasCitationIndex { library.append(.readingPath) }
      library.append(.keepOffline)
    }
    let sections = [
      opening, library, isRFC ? [.share] : [], inCollection ? [.removeFromCollection] : [],
    ]
    return sections.filter { !$0.isEmpty }
  }
}

extension DocumentMenus.Action {
  /// What this does for `id`, read at `section`: nil for a citation without the
  /// document's metadata, which there is nothing to cite from. With no `id`, a
  /// draft's (#728), only the text's own toggles do anything.
  public func effect(
    for id: DocumentID?, metadata: RFCMetadata?, section: String?
  ) -> DocumentMenus.Effect? {
    switch self {
    case .copyCitation(let style):
      metadata.map {
        .copy(DocumentActions.citation($0, section: section, style: style), .citation)
      }
    case .copySectionLink:
      id.map { .copy(DocumentActions.sectionLink(id: $0, section: section), .link) }
    case .toggleOriginalText: .toggleOriginalText
    case .toggleTranslation: .toggleTranslation
    case .openInfoPage: id.map { .open(RFCEditorEndpoints.infoPage($0)) }
    case .openErrata(let url), .openPrecedingDraft(let url): .open(url)
    case .openDatatracker: id.map { .open(RFCEditorEndpoints.datatracker($0)) }
    }
  }
}
