import Foundation
import RFCKit
import RFCReaderKit
import SwiftData

// Highlights (#522) and notes (#523), made and changed on the main context through
// `AnnotationStore`,
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

  private static func edit(_ context: ModelContext, _ undoManager: UndoManager?)
    -> AnnotationStore.Edit
  {
    AnnotationStore.Edit(
      context, undoManager: undoManager, onUndoFailure: UserDataMirror.logAnnotationUndoFailure)
  }

  /// Highlights `range` of `document`'s model text, merging it with what it overlaps.
  /// Answers the highlight, or nil when none was made.
  @discardableResult
  func highlight(
    _ range: Range<Int>, of document: DocumentID, in model: ModelText, color: HighlightColor,
    undoManager: UndoManager?
  ) -> UUID? {
    lastHighlightColor = color
    var made: UUID?
    editAnnotations { context in
      made = try AnnotationStore.highlight(
        range, of: document, in: model, color: color, edit: Self.edit(context, undoManager))
    }
    return made
  }

  func setHighlightColor(_ color: HighlightColor, of identifier: UUID, undoManager: UndoManager?) {
    lastHighlightColor = color
    editAnnotations { context in
      try AnnotationStore.setColor(
        color, of: identifier, edit: Self.edit(context, undoManager))
    }
  }

  func deleteHighlight(_ identifier: UUID, undoManager: UndoManager?) {
    editAnnotations { context in
      try AnnotationStore.delete(
        identifier, edit: Self.edit(context, undoManager))
    }
  }

  /// Puts an ambiguous highlight at the place the reader chose.
  func placeHighlight(_ identifier: UUID, at target: Target, undoManager: UndoManager?) {
    editAnnotations { context in
      try AnnotationStore.place(
        identifier, at: target, edit: Self.edit(context, undoManager))
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

  // MARK: - Notes

  /// Saves a note's text: made the first time it has some, deleted when it has none.
  func saveNote(_ identifier: UUID, on owner: NoteOwner, of document: DocumentID, body: String) {
    editAnnotations { context in
      try AnnotationStore.saveNote(
        identifier, on: owner, of: document, body: body, context: context)
    }
  }

  func deleteNote(_ identifier: UUID, undoManager: UndoManager?) {
    editAnnotations { context in
      try AnnotationStore.deleteNote(identifier, edit: Self.edit(context, undoManager))
    }
  }

  /// What a reader's build found of notes: own ranges that moved, and notes whose
  /// highlight is gone, put on the highlight that covers them.
  func recordNotePlacement(_ placement: NotePlacement) {
    guard !placement.relocations.isEmpty || !placement.repoints.isEmpty else { return }
    editAnnotations { context in
      for (identifier, target) in placement.relocations {
        try AnnotationStore.recordNoteRelocation(of: identifier, at: target, context: context)
      }
      for (identifier, highlight) in placement.repoints {
        try AnnotationStore.repointNote(identifier, to: highlight, context: context)
      }
    }
  }
}
