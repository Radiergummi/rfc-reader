import Foundation

/// Drawings and their captions (#361): artwork shaped like a drawing says so with
/// RFCXML's `ascii-art`, and a `Figure 3: …` line under a verbatim block makes it a
/// figure with that number and title, as a `Table 3: …` line under a table titles it.
extension LegacyTextParser {
  /// A caption as the line or two under a figure or a table write it.
  struct Caption: Equatable {
    var isTable: Bool
    /// The number when it is a whole one, as RFCXML numbers figures and tables; nil
    /// for one numbered by section (`Figure 2.1`) or lettered (`Figure 8A`).
    var number: Int?
    /// What the document calls it, `Figure 2.1`, its word as written.
    var label: String
    var title: String?

    /// The title the block is given: its own, beside a whole number the reader puts
    /// back in front of it, and otherwise the label and the title together, so a
    /// figure numbered by section keeps the name its prose calls it by.
    var blockTitle: String? {
      if number != nil { return title }
      return title.map { "\(label): \($0)" } ?? label
    }
  }

  /// The caption `lines` are, or nil: one or two lines, the label opening the first
  /// with the title after it and running onto the second, or the title on the first
  /// and the label alone on the second. A label followed by words with no separator,
  /// `Figure 3 shows …`, is a sentence and not a caption.
  static func caption(_ lines: [String]) -> Caption? {
    // Most artwork is longer than a caption: told before any line is trimmed.
    guard lines.lazy.filter({ !$0.isBlank }).prefix(3).count <= 2 else { return nil }
    let lines = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    guard (1...2).contains(lines.count) else { return nil }
    if let label = captionLabel(lines[0]) {
      var label = label
      let title = ([label.title].compactMap { $0 } + lines.dropFirst()).joined(separator: " ")
        .collapsingWhitespace()
      label.title = title.isEmpty ? nil : title
      return label
    }
    guard lines.count == 2, var label = captionLabel(lines[1]), label.title == nil,
      !DrawingShape.looksLikeDrawing(lines[0])
    else { return nil }
    label.title = lines[0].collapsingWhitespace()
    return label
  }

  private static func captionLabel(_ line: String) -> Caption? {
    guard let match = line.wholeMatch(of: captionPattern) else { return nil }
    let rest = match.rest.drop { $0 == " " }
    let separated = match.separator != nil || rest.isEmpty
    // Without a separator, a title opens with a capital, or is a parenthesis alone, as
    // `(Continued)` is: `Figure 1 (above) shows …` is a sentence.
    let parenthesized = rest.first == "(" && rest.firstIndex(of: ")") == rest.indices.last
    guard separated || rest.first?.isUppercase == true || parenthesized else { return nil }
    let title = rest.drop { ".:-–— ".contains($0) }
    // A title is words: what opens with a quote or a brace is code a label stands in.
    guard title.first.map({ $0.isLetter || $0.isNumber || $0 == "(" }) ?? true else {
      return nil
    }
    return Caption(
      isTable: match.word == "Table", number: Int(match.number),
      label: "\(match.word) \(match.number)", title: title.isEmpty ? nil : String(title))
  }

  private static let captionPattern = Pattern(
    #/(?<word>Figure|Fig\.|Table)\s+(?<number>\d+(?:[.-]\d+)*[A-Za-z]?(?:\s?\([a-z0-9]\))?)(?<separator>\.|:|\s*--?|\s*[–—])?(?<rest>.*)/#
  )

  /// Each section's blocks with their drawings typed and their captions taken in. A
  /// figure or table numbered as a whole number has no anchor: its part number,
  /// `figure-N`, is its ID, as RFCXML's prep gives it one, and an anchor spelled the
  /// same would declare it twice.
  static func figuringCaptions(_ sections: [Section]) -> [Section] {
    var taken = Set<String>()
    func visit(_ section: Section) -> Section {
      var section = section
      section.blocks = figuring(section.blocks, taken: &taken)
      section.subsections = section.subsections.map(visit)
      return section
    }
    return sections.map(visit)
  }

  /// `blocks` with their drawings typed and their captions taken in (`figuringCaptions`).
  static func figuring(_ blocks: [Block]) -> [Block] {
    var taken = Set<String>()
    return figuring(blocks, taken: &taken)
  }

  private static func figuring(_ blocks: [Block], taken: inout Set<String>) -> [Block] {
    var result: [Block] = []
    for block in blocks {
      guard case .preformatted(let verbatim) = block else {
        result.append(block)
        continue
      }
      if verbatim.kind == .artwork, verbatim.type == nil,
        let caption = caption(verbatim.text.components(separatedBy: "\n")),
        let captioned = captioning(&result, with: caption, taken: &taken)
      {
        result.append(captioned)
        continue
      }
      result.append(.preformatted(typingDrawing(verbatim)))
    }
    return result
  }

  /// The block above a caption, taken off `result` and given the caption, or nil when
  /// there is none it captions: a table for a table's caption, and for any caption a
  /// verbatim block, which becomes a figure (`takingFigure`). A caption with no title
  /// of its own, `Figure 7.`, takes the line of words above it that reads as one, or
  /// the drawing's last line where the drawing joined it.
  private static func captioning(
    _ result: inout [Block], with caption: Caption, taken: inout Set<String>
  ) -> Block? {
    var caption = caption
    // A number is the document's once: its part number, `figure-3`, is an ID. A second
    // figure the document numbers the same, one continued over a page, keeps its label.
    let part = caption.number.map { "\(caption.isTable ? "table" : "figure")-\($0)" }
    if let part, taken.contains(part) { caption.number = nil }
    switch result.last {
    case .table(var table)? where caption.isTable && table.title == nil:
      result.removeLast()
      table.title = caption.blockTitle
      table.number = caption.number
      if let part { taken.insert(part) }
      return .table(table)
    case .preformatted(let above)?:
      guard var blocks = takingFigure(from: &result, above: above) else { return nil }
      if caption.title == nil, let title = takingTitle(from: &blocks) {
        caption.title = title
      } else if caption.title == nil, blocks.count == 1, above.kind == .artwork,
        let split = splittingTitle(above)
      {
        caption.title = split.title
        blocks = [.preformatted(split.drawing)]
      }
      // A table's caption under a block that is no table names a figure, numbered as
      // none of the document's figures are.
      if caption.isTable { caption.number = nil }
      if caption.number != nil, let part { taken.insert(part) }
      return .figure(
        Figure(
          title: caption.blockTitle, number: caption.number,
          blocks: blocks.map { block in
            guard case .preformatted(let verbatim) = block else { return block }
            return .preformatted(typingDrawing(verbatim))
          }))
    default:
      return nil
    }
  }

  /// The blocks a caption under `above`, the last of `result`, captions, taken off
  /// `result`: `above`, or a drawing with a line or two of words between it and the
  /// caption, its title or a note under it (RFC 793's `TCP Header Format`, then a note,
  /// then `Figure 3.`), which are the figure's as well. Nil when the lines of words
  /// stand under no drawing, as one under a ladder read as a list does, or under code
  /// they may be the prose of: a title alone is no figure.
  private static func takingFigure(from result: inout [Block], above: Preformatted) -> [Block]? {
    var lines = 0
    while lines < 2, result.count > lines,
      case .preformatted(let line) = result[result.count - 1 - lines], line.kind == .artwork,
      isLineOfWords(line.text)
    {
      lines += 1
    }
    if lines == 0 {
      result.removeLast()
      return [.preformatted(above)]
    }
    let start = result.count - 1 - lines
    guard start >= 0, case .preformatted(let drawing) = result[start],
      DrawingShape.looksLikeDrawing(drawing.text)
    else {
      return nil
    }
    let blocks = Array(result[start...])
    result.removeSubrange(start...)
    return blocks
  }

  /// The first line of words under the drawing that reads as a title, taken out of
  /// `blocks`, which `takingFigure` gave.
  private static func takingTitle(from blocks: inout [Block]) -> String? {
    for index in blocks.indices.dropFirst() {
      guard case .preformatted(let line) = blocks[index], let title = titleLine(line.text)
      else { continue }
      blocks.remove(at: index)
      return title
    }
    return nil
  }

  /// Whether `text` is one line of words, not a drawing's.
  private static func isLineOfWords(_ text: String) -> Bool {
    let line = text.trimmingCharacters(in: .whitespaces)
    return !line.isEmpty && !line.contains("\n") && line.contains(where: \.isLetter)
      && !DrawingShape.looksLikeDrawing(line)
  }

  /// The line `text` is when it is a title: one line of words that is no sentence,
  /// which a title does not end with a period to be, and not a drawing's labels spread
  /// across a line (`Before        After`), with its spaces made single as `<name>`
  /// reads them.
  private static func titleLine(_ text: String) -> String? {
    let line = text.trimmingCharacters(in: .whitespaces)
    guard isLineOfWords(line), !line.hasSuffix("."), !line.contains("   ") else { return nil }
    return line.collapsingWhitespace()
  }

  /// A drawing whose last stretch, past a blank line, is a title: how a figure's
  /// title under it arrives when the drawing joined it (#437). Nil when there is no
  /// such stretch, or what is above it is no drawing: the last line of a trace or an
  /// example is its own.
  private static func splittingTitle(_ verbatim: Preformatted) -> (
    drawing: Preformatted, title: String
  )? {
    var lines = verbatim.text.components(separatedBy: "\n")
    while lines.last?.isBlank == true { lines.removeLast() }
    guard let last = lines.last, let title = titleLine(last), lines.count >= 3,
      lines[lines.count - 2].isBlank
    else { return nil }
    lines.removeLast()
    while lines.last?.isBlank == true { lines.removeLast() }
    let text = lines.joined(separator: "\n")
    guard DrawingShape.looksLikeDrawing(text) else { return nil }
    var drawing = verbatim
    drawing.text = text
    return (drawing, title)
  }

  /// Artwork shaped like a drawing, typed `ascii-art` as RFCXML types one.
  private static func typingDrawing(_ verbatim: Preformatted) -> Preformatted {
    guard verbatim.kind == .artwork, verbatim.type == nil,
      DrawingShape.looksLikeDrawing(verbatim.text)
    else { return verbatim }
    var typed = verbatim
    typed.type = "ascii-art"
    return typed
  }
}
