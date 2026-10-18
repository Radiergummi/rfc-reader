import Foundation

/// The inspector's two panes, which share one slot beside the reader: the
/// document's navigation (contents and references) and what is known about it.
///
/// Each has its own toolbar button, and they behave as Pages' Format and Document
/// buttons do: a button opens a closed inspector on its pane, swaps an open one to
/// it, and closes the inspector when its pane is already showing.
public enum InspectorPane: String, Codable, Sendable {
  case navigation
  case info

  /// What pressing `pressed`'s button does to an inspector that is `isOpen`,
  /// `showing` a pane. Closing keeps the pane, so the next open shows it again.
  public static func pressing(
    _ pressed: InspectorPane, isOpen: Bool, showing: InspectorPane
  ) -> (isOpen: Bool, pane: InspectorPane) {
    if isOpen, showing == pressed { return (false, showing) }
    return (true, pressed)
  }

  /// What `pressed`'s menu item is called: what pressing it will do, as View ▸
  /// Show Sidebar says (#761).
  public static func menuTitle(
    _ pressed: InspectorPane, isOpen: Bool, showing: InspectorPane, locale: Locale = .interface
  ) -> String {
    let opens = pressing(pressed, isOpen: isOpen, showing: showing).isOpen
    return switch (pressed, opens) {
    case (.navigation, true): String(kit: "Show Contents", locale: locale)
    case (.navigation, false): String(kit: "Hide Contents", locale: locale)
    case (.info, true): String(kit: "Show Info", locale: locale)
    case (.info, false): String(kit: "Hide Info", locale: locale)
    }
  }

  /// Whether `pane` has anything to show for a document `isDescribed` by the index
  /// and whose body is here or not (#325). Info needs only the index's entry, so a
  /// document still loading, or one that failed to or was offline, has it; the
  /// navigation pane's contents, references and requirements come with the body.
  public static func hasContent(_ pane: InspectorPane, hasBody: Bool, isDescribed: Bool) -> Bool {
    switch pane {
    case .info: isDescribed || hasBody
    case .navigation: hasBody
    }
  }

  /// What the navigation pane's contents, references and requirements show.
  public enum NavigationContent: Sendable {
    /// The lists themselves.
    case lists
    /// Progress: the body is on its way.
    case loading
    /// That the document has not loaded: its load failed, or was offline, and
    /// nothing more is coming.
    case notLoaded
    /// That the RFC is its PDF or PostScript original, which has no lists (#207);
    /// `PublishedOriginalPage.Status.panelExplanation` says which.
    case publishedOriginal
  }

  /// What the navigation pane shows for a document whose body is here or not, and
  /// is still `isLoading` or not (#325), or that `readsAsOriginal` (#207): a scan
  /// has no text, and a pointer's is not the RFC.
  public static func navigationContent(
    hasBody: Bool, isLoading: Bool, readsAsOriginal: Bool = false
  ) -> NavigationContent {
    if readsAsOriginal { return .publishedOriginal }
    if hasBody { return .lists }
    return isLoading ? .loading : .notLoaded
  }
}
