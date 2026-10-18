import Foundation
import RFCKit
import RFCReaderKit
import SwiftData

// Highlights (#522), made and changed on the main context through `AnnotationStore`,
// which decides what each change does; a failure is logged, as a collection's is.

extension LibraryModel {
  /// The color a highlight is made in when none is chosen, and the one the menus
  /// offer first: the last one chosen. Per device, as a tool's last setting is.
  var lastHighlightColor: HighlightColor {
    get {
      UserDefaults.standard.string(forKey: Self.lastHighlightColorKey).map(
        HighlightColor.init(name:))
        ?? .default
    }
    set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.lastHighlightColorKey) }
  }

  private static let lastHighlightColorKey = "lastHighlightColor"

  /// Highlights `range` of `document`'s model text, merging it with what it overlaps.
  func highlight(
    _ range: Range<Int>, of document: DocumentID, in model: ModelText, color: HighlightColor,
    undoManager: UndoManager?
  ) {
    lastHighlightColor = color
    editAnnotations { context in
      try AnnotationStore.highlight(
        range, of: document, in: model, color: color, undoManager: undoManager,
        onUndoFailure: UserDataMirror.logAnnotationUndoFailure, context: context)
    }
  }

  func setHighlightColor(_ color: HighlightColor, of identifier: UUID, undoManager: UndoManager?) {
    lastHighlightColor = color
    editAnnotations { context in
      try AnnotationStore.setColor(
        color, of: identifier, undoManager: undoManager,
        onUndoFailure: UserDataMirror.logAnnotationUndoFailure, context: context)
    }
  }

  func deleteHighlight(_ identifier: UUID, undoManager: UndoManager?) {
    editAnnotations { context in
      try AnnotationStore.delete(
        identifier, undoManager: undoManager,
        onUndoFailure: UserDataMirror.logAnnotationUndoFailure, context: context)
    }
  }

  /// Puts an ambiguous highlight at the place the reader chose.
  func placeHighlight(_ identifier: UUID, at target: Target, undoManager: UndoManager?) {
    editAnnotations { context in
      try AnnotationStore.place(
        identifier, at: target, undoManager: undoManager,
        onUndoFailure: UserDataMirror.logAnnotationUndoFailure, context: context)
    }
  }

  /// Where a reader's build found highlights that moved, kept beside where they were
  /// made, so relocation does not run again on every open.
  func recordHighlightRelocations(_ relocations: [UUID: Target]) {
    editAnnotations { context in
      for (identifier, target) in relocations {
        try AnnotationStore.recordRelocation(of: identifier, at: target, context: context)
      }
    }
  }
}
