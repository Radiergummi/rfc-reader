import Foundation

/// The column a collapsed split view shows, as on an iPhone, where the sidebar, the
/// list and the document are one stack (#256).
///
/// One value, derived from what the scene has chosen rather than from the last tap:
/// a deep link opens a document whichever column is on screen, and the stack has to
/// follow it there. Going back is the other direction, and clears what the column
/// left behind, so a list does not keep a row selected that is no longer pushed.
public enum CompactColumn: Sendable, Equatable {
  case sidebar
  case content
  case detail

  /// The deepest column the scene's state reaches: the document when one is shown,
  /// the list when a filter is selected, the sidebar otherwise.
  public static func showing(document: Bool, filter: Bool) -> CompactColumn {
    if document { return .detail }
    return filter ? .content : .sidebar
  }

  /// What going back to this column clears: the document when the column is not
  /// the document's, and the sidebar's selected filter when it is the sidebar.
  public var clears: (document: Bool, filter: Bool) {
    switch self {
    case .sidebar: (true, true)
    case .content: (true, false)
    case .detail: (false, false)
    }
  }
}
