import Foundation

/// How Copy as Quote writes a line of prose in Markdown (#1003).
///
/// The quote's plain-text flavor is its Markdown too, and Slack and chat apps paste
/// plain text and show a backslash as it is. So a quoted line escapes what would
/// render as markup where it is pasted, and nothing else: unlike the Markdown export,
/// it leaves a reference's label, `[RFC 9111]`, as it reads. Each quoted line is a
/// paragraph of its own, so a `|` never opens a table and is not escaped.
extension QuoteCitation {
  /// `line` without its indentation, which would make it code from four columns on,
  /// with a backslash before what would open a block at its start, and before what
  /// would make emphasis, strikethrough, a code span, a link, an entity or an escape
  /// within it. A `<` is an entity instead: `\<` renders only where Markdown is
  /// CommonMark, an entity wherever it becomes HTML, and unescaped, GitHub takes
  /// `<field-name>` for a tag and drops it.
  static func escapedMarkdownLine(_ line: String) -> String {
    let characters = Array(line.drop { $0 == " " || $0 == "\t" })
    var escaped = blockMarker(in: characters)
    escaped.formUnion(emphasisDelimiters(in: characters))
    escaped.formUnion(codeSpanDelimiters(in: characters))
    escaped.formUnion(linkOpeners(in: characters))
    for (index, character) in characters.enumerated() {
      let next = index + 1 < characters.count ? characters[index + 1] : nil
      if character == "\\", let next, next.isASCII, isPunctuation(next) {
        escaped.insert(index)
      } else if character == "&", opensEntity(characters[(index + 1)...]) {
        escaped.insert(index)
      }
    }

    var result = ""
    for (index, character) in characters.enumerated() {
      if character == "<" {
        result += "&lt;"
        continue
      }
      if escaped.contains(index) { result.append("\\") }
      result.append(character)
    }
    return result
  }

  /// The characters of what would open a block at the start of `line`: an ATX
  /// heading, a list item, a nested quote, a thematic break, a setext underline, a
  /// fence, or a link reference definition, which would take the line out of the
  /// quote altogether.
  private static func blockMarker(in line: [Character]) -> Set<Int> {
    guard let first = line.first else { return [] }
    func endsMarker(_ index: Int) -> Bool {
      index == line.count || line[index] == " " || line[index] == "\t"
    }
    let run = line.prefix { $0 == first }.count
    func isOnly(_ character: Character) -> Bool {
      line.allSatisfy { $0 == character || $0 == " " || $0 == "\t" }
    }

    if first == ">" { return [0] }
    if first == "#", run <= 6, endsMarker(run) { return [0] }
    if "-+*".contains(first), endsMarker(1) { return [0] }
    if "-*_".contains(first), isOnly(first), line.count(where: { $0 == first }) >= 3 { return [0] }
    if first == "=", isOnly("=") { return [0] }
    if "`~".contains(first), run >= 3 { return Set(0..<run) }
    if first == "[", let close = line.firstIndex(of: "]"), close + 1 < line.count,
      line[close + 1] == ":"
    {
      return [0]
    }
    let digits = line.prefix { $0.isASCII && $0.isNumber }.count
    if (1...9).contains(digits), digits < line.count, ".)".contains(line[digits]),
      endsMarker(digits + 1)
    {
      return [digits]
    }
    return []
  }

  /// The runs of `*`, `_` and `~` (one or two of them, as GitHub strikes through)
  /// that could open emphasis with a run later in the line that could close it, by
  /// CommonMark's flanking rules: both runs of such a pair, every character of each.
  /// A `~` run closes only one as long as it. The rule of three is not applied, so a
  /// rare pair it rules out is escaped all the same.
  private static func emphasisDelimiters(in line: [Character]) -> Set<Int> {
    struct Run {
      var range: Range<Int>
      var character: Character
      var opens: Bool
      var closes: Bool
    }
    func isSpace(_ character: Character?) -> Bool { character?.isWhitespace ?? true }
    func isMark(_ character: Character?) -> Bool { character.map(isPunctuation) ?? false }

    var runs: [Run] = []
    var start = 0
    while start < line.count {
      let character = line[start]
      var end = start + 1
      while end < line.count, line[end] == character { end += 1 }
      if "*_~".contains(character), character != "~" || end - start <= 2 {
        let before = start > 0 ? line[start - 1] : nil
        let after = end < line.count ? line[end] : nil
        let left = !isSpace(after) && (!isMark(after) || isSpace(before) || isMark(before))
        let right = !isSpace(before) && (!isMark(before) || isSpace(after) || isMark(after))
        // An `_` within a word is never emphasis.
        let isUnderscore = character == "_"
        runs.append(
          Run(
            range: start..<end, character: character,
            opens: isUnderscore ? left && (!right || isMark(before)) : left,
            closes: isUnderscore ? right && (!left || isMark(after)) : right))
      }
      start = end
    }

    var escaped = Set<Int>()
    for (index, opener) in runs.enumerated() where opener.opens {
      let closer = runs[(index + 1)...].first {
        $0.character == opener.character && $0.closes
          && (opener.character != "~" || $0.range.count == opener.range.count)
      }
      if let closer {
        escaped.formUnion(opener.range)
        escaped.formUnion(closer.range)
      }
    }
    return escaped
  }

  /// The backticks of every code span in `line`: a run, and the next run as long as
  /// it, which closes it. A run with none is literal.
  private static func codeSpanDelimiters(in line: [Character]) -> Set<Int> {
    var runs: [Range<Int>] = []
    var start = 0
    while start < line.count {
      var end = start + 1
      while end < line.count, line[end] == line[start] { end += 1 }
      if line[start] == "`" { runs.append(start..<end) }
      start = end
    }

    var escaped = Set<Int>()
    var index = 0
    while index < runs.count {
      let opener = runs[index]
      if let closer = runs[(index + 1)...].firstIndex(where: { $0.count == opener.count }) {
        escaped.formUnion(opener)
        escaped.formUnion(runs[closer])
        index = closer + 1
      } else {
        index += 1
      }
    }
    return escaped
  }

  /// The `[` of every bracketed text a `(` or a `[` follows, which would make it a
  /// link or an image. A bracketed text alone, a reference's label, is not one.
  private static func linkOpeners(in line: [Character]) -> Set<Int> {
    var openers: [Int] = []
    var escaped = Set<Int>()
    for (index, character) in line.enumerated() {
      if character == "[" {
        openers.append(index)
      } else if character == "]" {
        let opener = openers.popLast()
        if let opener, index + 1 < line.count, "([".contains(line[index + 1]) {
          escaped.insert(opener)
        }
      }
    }
    return escaped
  }

  /// Whether what follows an `&` makes it an entity or a numeric character reference,
  /// which is at most 33 characters long.
  private static func opensEntity(_ rest: ArraySlice<Character>) -> Bool {
    String(rest.prefix(33)).prefixMatch(
      of: /#[0-9]{1,7};|#[xX][0-9a-fA-F]{1,6};|[A-Za-z][A-Za-z0-9]{0,31};/) != nil
  }

  private static func isPunctuation(_ character: Character) -> Bool {
    character.isPunctuation || character.isSymbol
  }
}
