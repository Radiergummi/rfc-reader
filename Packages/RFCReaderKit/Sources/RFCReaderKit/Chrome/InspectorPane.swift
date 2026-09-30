/// The inspector's two panes, which share one slot beside the reader: the
/// document's navigation (contents and references) and what is known about it.
///
/// Each has its own toolbar button, and they behave as Pages' Format and Document
/// buttons do: a button opens a closed inspector on its pane, swaps an open one to
/// it, and closes the inspector when its pane is already showing.
public enum InspectorPane: Sendable {
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
}
