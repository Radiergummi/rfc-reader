import Foundation

/// What a block's context menu offers a note on (#523): the figure, the table or the
/// paragraph a storage offset is in, as a range covering exactly that block, or, on a
/// heading, its section.
public enum NoteBlock: Sendable, Equatable {
  case figure(Target)
  case table(Target)
  case paragraph(Target)
  case section(String)

  /// What the note would be on.
  public var target: Target {
    switch self {
    case .figure(let target), .table(let target), .paragraph(let target): target
    case .section(let anchor): .section(anchor)
    }
  }

  /// The block at storage offset `location` of `built`. Nil where nothing of the
  /// model is, as on a chip's character alone, and in a translation's build.
  public init?(at location: Int, in built: BuiltDocument) {
    let text = built.text
    guard !built.isTranslation, location >= 0, location < text.length else { return nil }
    if let anchor = text.attribute(.rfcAnchor, at: location, effectiveRange: nil) as? String,
      built.positions.model.span(of: anchor) != nil
    {
      self = .section(anchor)
      return
    }
    var storage = NSRange(location: 0, length: 0)
    var make: (Target) -> NoteBlock = NoteBlock.paragraph
    if text.attribute(.rfcVerbatim, at: location, effectiveRange: nil) != nil {
      _ = text.attribute(
        .rfcVerbatim, at: location, longestEffectiveRange: &storage,
        in: NSRange(location: 0, length: text.length))
      make = NoteBlock.figure
    } else if let run = text.decorationRun(at: location), run.decoration == .table {
      storage = run.range
      make = NoteBlock.table
    } else {
      let string = text.string as NSString
      storage = string.paragraphRange(for: NSRange(location: location, length: 0))
      // Without its line end, which joins it to the next and belongs to neither.
      while storage.length > 0,
        "\n\u{2029}".utf16.contains(string.character(at: NSMaxRange(storage) - 1))
      {
        storage.length -= 1
      }
    }
    let model = built.positions.model
    guard let range = built.positions.modelRange(forStorage: storage),
      let target = Target(covering: range, in: model)
    else { return nil }
    self = make(target)
  }
}
