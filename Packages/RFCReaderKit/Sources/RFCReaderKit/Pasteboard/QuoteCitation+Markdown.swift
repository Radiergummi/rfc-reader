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
      if escaped.contains(index) {
        result.append("\\")
      }
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
  ///
  /// CommonMark 0.31 counts a symbol such as `≤` or `©` as punctuation, and 0.29,
  /// which GitHub's cmark-gfm follows, does not, so a run opens or closes here where
  /// it would under either.
  private static func emphasisDelimiters(in line: [Character]) -> Set<Int> {
    struct Run {
      var range: Range<Int>
      var character: Character
      var opens: Bool
      var closes: Bool
    }

    var runs: [Run] = []
    for range in characterRuns(in: line) {
      let character = line[range.lowerBound]
      guard "*_~".contains(character), character != "~" || range.count <= 2 else {
        continue
      }
      let before = range.lowerBound > 0 ? line[range.lowerBound - 1] : nil
      let after = range.upperBound < line.count ? line[range.upperBound] : nil
      let flankings = [isPunctuation, isPunctuationInCommonMark029].map { isMark in
        flanking(of: character, between: before, and: after, punctuation: isMark)
      }
      runs.append(
        Run(
          range: range, character: character,
          opens: flankings.contains { $0.opens },
          closes: flankings.contains { $0.closes }))
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

  /// Whether a run of `character` between `before` and `after` can open and close
  /// emphasis, by CommonMark's flanking rules with `punctuation` as their punctuation.
  private static func flanking(
    of character: Character, between before: Character?, and after: Character?,
    punctuation: (Character) -> Bool
  ) -> (opens: Bool, closes: Bool) {
    func isSpace(_ character: Character?) -> Bool {
      guard let character else {
        return true
      }
      return isUnicodeWhitespace(character)
    }
    func isMark(_ character: Character?) -> Bool {
      character.map(punctuation) ?? false
    }

    let left = !isSpace(after) && (!isMark(after) || isSpace(before) || isMark(before))
    let right = !isSpace(before) && (!isMark(before) || isSpace(after) || isMark(after))
    // An `_` within a word is never emphasis.
    if character == "_" {
      return (left && (!right || isMark(before)), right && (!left || isMark(after)))
    }
    return (left, right)
  }

  /// Every backtick in `line` when it has a code span, which it has when two runs of
  /// backticks are as long as each other, and none when it has none. All of them,
  /// because a backslash does not escape a backtick that closes a span an unescaped
  /// one opens: escaping only a span's own runs would leave one between them to open
  /// a span that an escaped one closes.
  private static func codeSpanDelimiters(in line: [Character]) -> Set<Int> {
    let lengths = characterRuns(in: line)
      .filter { line[$0.lowerBound] == "`" }
      .map(\.count)
    guard Set(lengths).count < lengths.count else { return [] }
    return Set(line.indices.filter { line[$0] == "`" })
  }

  /// The `[` of every bracketed text a `(` or a `[` follows, which would make it a
  /// link or an image, and of every `[` still open before it, which its `]` would
  /// close instead once that one is escaped. A bracketed text alone, a reference's
  /// label, is not one.
  private static func linkOpeners(in line: [Character]) -> Set<Int> {
    var openers: [Int] = []
    var escaped = Set<Int>()
    for (index, character) in line.enumerated() {
      if character == "[" {
        openers.append(index)
      } else if character == "]" {
        guard let opener = openers.popLast() else { continue }
        if index + 1 < line.count, "([".contains(line[index + 1]) {
          escaped.insert(opener)
          escaped.formUnion(openers)
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

  /// The ranges of `line`'s runs of one character repeated, in order.
  private static func characterRuns(in line: [Character]) -> [Range<Int>] {
    var runs: [Range<Int>] = []
    var start = 0
    while start < line.count {
      var end = start + 1
      while end < line.count, line[end] == line[start] {
        end += 1
      }
      runs.append(start..<end)
      start = end
    }
    return runs
  }

  /// Punctuation as CommonMark 0.31 has it: any Unicode punctuation or symbol.
  private static func isPunctuation(_ character: Character) -> Bool {
    character.isPunctuation || character.isSymbol
  }

  /// Punctuation as CommonMark 0.29 has it: ASCII punctuation, and Unicode
  /// punctuation but not symbols.
  private static func isPunctuationInCommonMark029(_ character: Character) -> Bool {
    character.isPunctuation || (character.isASCII && character.isSymbol)
  }

  /// Whitespace as CommonMark has it: a space separator, a tab, a line feed, a form
  /// feed or a carriage return, which leaves out what else Swift counts as whitespace.
  private static func isUnicodeWhitespace(_ character: Character) -> Bool {
    if "\t\n\u{0C}\r".contains(character) {
      return true
    }
    return character.unicodeScalars.first?.properties.generalCategory == .spaceSeparator
  }
}
