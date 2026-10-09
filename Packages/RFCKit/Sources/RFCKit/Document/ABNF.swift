import Foundation

/// Recognizes ABNF by parsing it (#45).
///
/// ABNF is specified by RFC 5234, so whether a block of legacy artwork is a grammar
/// has an exact answer: try to parse it. This is a strict parser of RFC 5234, with the
/// RFC 7405 `%s`/`%i` case prefixes and the `#` list operator of RFC 9110 §5.6.1 and
/// RFC 2616, which HTTP-family grammars old and new use. It is tolerant only of what
/// the 72-column text format imposes on a grammar: the block's common indentation, a
/// rule continuing on any line set deeper than the line it starts on, and a comment
/// running from `;` to the end of its line.
///
/// Parsing alone is not quite enough: `count = max;` is a valid rule, with one element
/// and a comment, and so is a line of C or of a configuration file. `recognizes(_:)`
/// asks for more than one rule, or for syntax only a grammar has.
public enum ABNF {
  /// The notation a grammar is written in: RFC 5234's, which alternates with `/`, or
  /// the one RFC 822 and RFC 2616 write their grammars in, which alternates with `|`
  /// and has no `=/` (#696). The legacy parser types a grammar in the second as
  /// `abnf822`, which no RFC 5234 tool reads.
  public enum Dialect: Sendable {
    case rfc5234
    case rfc822

    /// What sets one alternative off from the next.
    var alternative: Character {
      switch self {
      case .rfc5234: "/"
      case .rfc822: "|"
      }
    }
  }

  public struct Rule: Sendable, Hashable {
    public var name: String
    /// A `=/` rule, adding alternatives to one defined before it.
    public var isIncremental: Bool
    /// The rule names the definition refers to, each once whatever its case, as first
    /// spelled and in order of first mention.
    var references: [String]
    /// Whether the definition uses syntax only a grammar has: an alternative (`/`), a
    /// repetition (`*`, `#`, or a count), an option (`[ ]`), a quoted literal or a
    /// numeric value (`%x41`). Groups and prose values (`<…>`) are left out: code and
    /// placeholders have those too.
    var usesGrammarSyntax: Bool
    /// Whether the definition has a repetition (`*`, `#`, or a count) or a numeric value
    /// (`%x41`): the syntax no listing of settings or message layout has, which says a
    /// block defining a name twice is a grammar with an error in it.
    var usesRepetitionOrNumericValue: Bool
    /// Where the name is defined, in UTF-16 code units of the text as given (#185).
    public var nameRange: NSRange
    /// Every mention of a rule name in the definition, in order, each with its range in
    /// the text as given: what the reader links to the rule's definition (#185).
    public var uses: [Use]
    /// Whether a count runs into a name made only of hex digits, as in `4c0ffee`: valid
    /// ABNF by the letter, and a reason not to take the block for a grammar.
    var readsAsHexNumber: Bool
  }

  /// One mention of a rule name.
  public struct Use: Sendable, Hashable {
    public var name: String
    public var range: NSRange
  }

  /// How deep groups and options may nest. The parser recurses once per level, so a
  /// block nested without bound would exhaust the stack (#757); no grammar nests more
  /// than a handful.
  static let maximumNesting = 64

  /// Whether `text` is a grammar: it parses, and a rule uses syntax only a grammar has,
  /// or there are two rules or more and one refers to another. `token = 1*tchar` is one;
  /// `count = max;` is not, although it parses, and neither is a list of assignments in
  /// pseudocode (`smallest = unbounded`), whose rules refer to nothing among them.
  ///
  /// A hex number read as a count and a name, and a name defined twice in a block with
  /// no repetition or numeric value, parse but are not recognized: test vectors,
  /// listings of settings and message layouts read that way.
  static func recognizes(_ text: String, dialect: Dialect = .rfc5234) -> Bool {
    recognizes(blocks: [text], dialect: dialect)
  }

  /// Whether `blocks`, each parsed as a block of its own, with its own indentation, are
  /// one grammar together, as `recognizes(_:)` asks of one block: a grammar set a rule
  /// or a few at a time with blank lines between (#423). A name defined in two of them
  /// counts as one defined twice.
  static func recognizes(blocks: [String], dialect: Dialect = .rfc5234) -> Bool {
    var rules: [Rule] = []
    var definesANameTwice = false
    var defined: Set<String> = []
    for block in blocks {
      guard let parsed = parsed(block, dialect: dialect, locatingNames: false) else {
        return false
      }
      rules += parsed.rules
      definesANameTwice = definesANameTwice || parsed.definesANameTwice
      for rule in parsed.rules where !rule.isIncremental {
        if !defined.insert(rule.name.lowercased()).inserted { definesANameTwice = true }
      }
    }
    guard !rules.contains(where: \.readsAsHexNumber),
      !definesANameTwice || rules.contains(where: \.usesRepetitionOrNumericValue)
    else { return false }
    if rules.contains(where: \.usesGrammarSyntax) { return true }
    let names = Set(rules.map { $0.name.lowercased() })
    return rules.count >= 2
      && rules.contains { rule in
        rule.references.contains { reference in
          let reference = reference.lowercased()
          return reference != rule.name.lowercased() && names.contains(reference)
        }
      }
  }

  /// Whether `text` parses as ABNF, grammar or not, without locating the names the
  /// reader links.
  static func parses(_ text: String, dialect: Dialect = .rfc5234) -> Bool {
    parsed(text, dialect: dialect, locatingNames: false) != nil
  }

  /// The rules of `text`, or nil when it is not ABNF. Blank lines and lines holding
  /// only a comment are skipped; every other line either starts a rule at column 0 or
  /// continues the one before it, set deeper.
  public static func parse(_ text: String, dialect: Dialect = .rfc5234) -> [Rule]? {
    parsed(text, dialect: dialect, locatingNames: true)?.rules
  }

  /// The rules, and whether a name is defined with `=` twice, whatever its case: a
  /// grammar adds to a rule only with `=/`, but listings of settings and message
  /// layouts assign one name twice. Grammars in the legacy series do too, where `=/`
  /// or another name was meant, so `recognizes` refuses a repeated definition only in
  /// a block without a repetition or a numeric value.
  ///
  /// `locatingNames` is what the ranges cost: recognizing, which the legacy parser
  /// asks of every candidate block in the corpus, reads none, and gets empty ones.
  private static func parsed(_ text: String, dialect: Dialect, locatingNames: Bool)
    -> (rules: [Rule], definesANameTwice: Bool)?
  {
    var rules: [Rule] = []
    var defined: Set<String> = []
    var definesANameTwice = false
    // The rule being read: its lines joined, and where each character of it is in
    // `text`, in UTF-16 code units; nil for the space that joins two lines.
    var current: (source: [Character], offsets: [Int?])?
    func finishRule() -> Bool {
      guard let source = current else { return true }
      current = nil
      var parser = RuleParser(source.source, offsets: source.offsets, dialect: dialect)
      guard let rule = parser.rule() else { return false }
      if !rule.isIncremental, !defined.insert(rule.name.lowercased()).inserted {
        definesANameTwice = true
      }
      rules.append(rule)
      return true
    }
    let lines = text.components(separatedBy: "\n")
    // The block's own indentation is not the rule's: RFCXML keeps it inside
    // `<sourcecode>`, and a rule starts at the least indented line that is not only a
    // comment. A comment may sit further left than the rules it heads (RFC 9271).
    let indent =
      lines.filter { line in
        !line.isBlank && line.first { $0 != " " } != ";"
      }
      .map(\.leadingSpaceCount).min() ?? 0
    var lineStart = 0
    for line in lines {
      defer { lineStart += line.utf16.count + 1 }
      let unindented = line.dropFirst(min(indent, line.leadingSpaceCount))
      guard let content = withoutComment(unindented) else { return nil }
      guard content.contains(where: { !$0.isWhitespace }) else { continue }
      let offsets =
        !locatingNames
        ? []
        : content.indices.map { index -> Int? in
          lineStart + line.utf16.distance(from: line.startIndex, to: index)
        }
      if content.first?.isWhitespace == true {
        guard current != nil else { return nil }
        current?.source += [" "] + Array(content)
        if locatingNames { current?.offsets += [nil] + offsets }
      } else {
        guard finishRule() else { return nil }
        current = (Array(content), offsets)
      }
    }
    guard finishRule(), !rules.isEmpty else { return nil }
    return (rules, definesANameTwice)
  }

  /// The line up to a `;` that is not inside a quoted literal or a prose value, or nil
  /// when a literal or a prose value is still open at the end of the line: neither
  /// may span lines.
  private static func withoutComment(_ line: Substring) -> Substring? {
    var closing: Character?
    for index in line.indices {
      let character = line[index]
      if let expected = closing {
        if character == expected { closing = nil }
        continue
      }
      switch character {
      case "\"": closing = "\""
      case "<": closing = ">"
      case ";": return line[..<index]
      default: break
      }
    }
    return closing == nil ? line : nil
  }

  /// A recursive-descent parser for one rule, its continuation lines joined into it.
  private struct RuleParser {
    private let characters: [Character]
    /// Where each character is in the text as given; nil for a joining space.
    private let offsets: [Int?]
    private var position = 0
    /// How many groups and options enclose `position`.
    private var nesting = 0
    private var references: [String] = []
    private var uses: [Use] = []
    private var usesGrammarSyntax = false
    private var usesRepetitionOrNumericValue = false
    private var readsAsHexNumber = false
    private let dialect: Dialect

    init(_ characters: [Character], offsets: [Int?], dialect: Dialect) {
      self.characters = characters
      self.offsets = offsets
      self.dialect = dialect
    }

    /// `rulename defined-as elements`, and nothing after it.
    mutating func rule() -> Rule? {
      let start = position
      guard let name = ruleName() else { return nil }
      let nameRange = range(from: start)
      skipSpace()
      guard take("=") else { return nil }
      let isIncremental = dialect == .rfc5234 && take("/")
      skipSpace()
      guard alternation() else { return nil }
      skipSpace()
      guard position == characters.count else { return nil }
      return Rule(
        name: name, isIncremental: isIncremental, references: references,
        usesGrammarSyntax: usesGrammarSyntax,
        usesRepetitionOrNumericValue: usesRepetitionOrNumericValue,
        nameRange: nameRange, uses: uses, readsAsHexNumber: readsAsHexNumber)
    }

    /// The text as given from the character at `start` to the one before `position`:
    /// a name, which is ASCII and on one line, so one code unit a character.
    private func range(from start: Int) -> NSRange {
      guard start < offsets.count else { return NSRange(location: 0, length: 0) }
      return NSRange(location: offsets[start] ?? 0, length: position - start)
    }

    private var next: Character? {
      position < characters.count ? characters[position] : nil
    }

    private mutating func take(_ character: Character) -> Bool {
      guard next == character else { return false }
      position += 1
      return true
    }

    /// Skips the characters that are digits by `isDigit`, and says whether there were any.
    private mutating func skipDigits(_ isDigit: (Character) -> Bool) -> Bool {
      let start = position
      while let next, isDigit(next) { position += 1 }
      return position > start
    }

    private static func isDecimalDigit(_ character: Character) -> Bool {
      character.isASCII && character.isNumber
    }

    @discardableResult
    private mutating func skipSpace() -> Bool {
      let start = position
      while let next, next == " " || next == "\t" { position += 1 }
      return position > start
    }

    /// `ALPHA *(ALPHA / DIGIT / "-")`.
    private mutating func ruleName() -> String? {
      guard let first = next, first.isASCII, first.isLetter else { return nil }
      var name = ""
      while let next, isNameCharacter(next) {
        name.append(next)
        position += 1
      }
      return name
    }

    /// A character a rule name may continue with: `ALPHA / DIGIT / "-"`, and in RFC
    /// 822's dialect `_` too, which grammars of that time name rules with (RFC 1808's
    /// `net_loc`).
    private func isNameCharacter(_ character: Character) -> Bool {
      character.isASCII
        && (character.isLetter || character.isNumber || character == "-"
          || dialect == .rfc822 && character == "_")
    }

    /// `concatenation *(*c-wsp "/" *c-wsp concatenation)`, with `|` in RFC 822's
    /// dialect.
    private mutating func alternation() -> Bool {
      guard concatenation() else { return false }
      while true {
        let start = position
        skipSpace()
        guard take(dialect.alternative) else {
          position = start
          return true
        }
        usesGrammarSyntax = true
        skipSpace()
        guard concatenation() else { return false }
      }
    }

    /// `repetition *(1*c-wsp repetition)`: another repetition only after space, and only
    /// where one can begin.
    private mutating func concatenation() -> Bool {
      guard repetition() else { return false }
      while true {
        let start = position
        guard skipSpace(), let next, Self.beginsRepetition(next) else {
          position = start
          return true
        }
        guard repetition() else { return false }
      }
    }

    private static func beginsRepetition(_ character: Character) -> Bool {
      (character.isASCII && (character.isLetter || character.isNumber))
        || "*#([\"%<".contains(character)
    }

    /// `[repeat] element`, where `repeat` is a count, `n*m`, or the list's `n#m`.
    ///
    /// A count directly before a name made only of hex digits, perhaps after an `x`, is a
    /// hex number, not a repetition: test vectors are valid ABNF by the letter, `4c0ffee`
    /// reading as four of a rule named `c0ffee` and `0x7` as none of `x7`.
    private mutating func repetition() -> Bool {
      let counted = skipDigits(Self.isDecimalDigit)
      if take("*") || take("#") {
        _ = skipDigits(Self.isDecimalDigit)
        usesGrammarSyntax = true
        usesRepetitionOrNumericValue = true
      } else if counted {
        if startsHexNumber() { readsAsHexNumber = true }
        usesGrammarSyntax = true
        usesRepetitionOrNumericValue = true
      }
      return element()
    }

    /// Whether what follows a count reads as the rest of a hex number: hex digits, perhaps
    /// after an `x` and perhaps in parts joined by hyphens, as in `0x7f` or `7e0c-11ab`.
    private func startsHexNumber() -> Bool {
      var name = characters[position...].prefix(while: isNameCharacter)
      if name.first == "x" || name.first == "X" { name = name.dropFirst() }
      return name.split(separator: "-", omittingEmptySubsequences: false).allSatisfy { part in
        !part.isEmpty && part.allSatisfy(\.isHexDigit)
      }
    }

    private mutating func element() -> Bool {
      guard let next else { return false }
      switch next {
      case "(":
        position += 1
        return enclosedAlternation(closing: ")")
      case "[":
        position += 1
        usesGrammarSyntax = true
        return enclosedAlternation(closing: "]")
      case "\"":
        usesGrammarSyntax = true
        return delimitedValue(opening: "\"", closing: "\"")
      case "%":
        position += 1
        usesGrammarSyntax = true
        return numericOrCasedValue()
      case "<":
        return delimitedValue(opening: "<", closing: ">")
      default:
        let start = position
        guard let name = ruleName() else { return false }
        uses.append(Use(name: name, range: range(from: start)))
        // Rule names are case-insensitive: one name in two spellings is one reference.
        if !references.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
          references.append(name)
        }
        return true
      }
    }

    private mutating func enclosedAlternation(closing: Character) -> Bool {
      guard nesting < ABNF.maximumNesting else { return false }
      nesting += 1
      defer { nesting -= 1 }
      skipSpace()
      guard alternation() else { return false }
      skipSpace()
      return take(closing)
    }

    /// A quoted literal, `DQUOTE *(%x20-21 / %x23-7E) DQUOTE`, or a prose value, `<`
    /// then printable characters but `>`, then `>`.
    private mutating func delimitedValue(opening: Character, closing: Character) -> Bool {
      guard take(opening) else { return false }
      while let next, next != closing {
        guard let value = next.asciiValue, (0x20...0x7E).contains(value) else { return false }
        position += 1
      }
      return take(closing)
    }

    /// After `%`: `s` or `i` and a quoted literal (RFC 7405), or `x`, `d` or `b` and a
    /// number in that base, followed by `.`-joined numbers or one `-` range.
    private mutating func numericOrCasedValue() -> Bool {
      // The letters after `%` may be written in either case.
      guard let base = next?.lowercased().first, "sixdb".contains(base) else { return false }
      position += 1
      if base == "s" || base == "i" { return delimitedValue(opening: "\"", closing: "\"") }
      usesRepetitionOrNumericValue = true
      let isDigit: (Character) -> Bool =
        switch base {
        case "x": { $0.isHexDigit }
        case "d": Self.isDecimalDigit
        default: { $0 == "0" || $0 == "1" }
        }
      guard skipDigits(isDigit) else { return false }
      if take("-") { return skipDigits(isDigit) }
      while take(".") {
        guard skipDigits(isDigit) else { return false }
      }
      return true
    }
  }
}
