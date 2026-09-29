import Foundation

/// Recognises ABNF by parsing it (#45).
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
enum ABNF {
  struct Rule: Sendable, Hashable {
    var name: String
    /// A `=/` rule, adding alternatives to one defined before it.
    var isIncremental: Bool
    /// The rule names the definition refers to, each once, in order of first mention.
    var references: [String]
    /// Whether the definition uses syntax only a grammar has: an alternative (`/`), a
    /// repetition (`*`, `#`, or a count), an option (`[ ]`), a quoted literal or a
    /// numeric value (`%x41`). Groups and prose values (`<…>`) are left out: code and
    /// placeholders have those too.
    var usesGrammarSyntax: Bool
  }

  /// Whether `text` is a grammar: it parses, and a rule uses syntax only a grammar has,
  /// or there are two rules or more and one refers to another. `token = 1*tchar` is one;
  /// `count = max;` is not, although it parses, and neither is a list of assignments in
  /// pseudocode (`lowest = infinity`), whose rules refer to nothing among them.
  static func recognizes(_ text: String) -> Bool {
    guard let rules = parse(text) else { return false }
    if rules.contains(where: \.usesGrammarSyntax) { return true }
    let names = Set(rules.map { $0.name.lowercased() })
    return rules.count >= 2
      && rules.contains { rule in rule.references.contains { names.contains($0.lowercased()) } }
  }

  /// The rules of `text`, or nil when it is not ABNF. Blank lines and lines holding
  /// only a comment are skipped; every other line either starts a rule at column 0 or
  /// continues the one before it, set deeper.
  static func parse(_ text: String) -> [Rule]? {
    var rules: [Rule] = []
    var current: String?
    func finishRule() -> Bool {
      guard let source = current else { return true }
      current = nil
      var parser = RuleParser(source)
      guard let rule = parser.rule() else { return false }
      rules.append(rule)
      return true
    }
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    // The block's own indentation is not the rule's: RFCXML keeps it inside
    // `<sourcecode>`, and a rule starts at the least indented line that is not only a
    // comment. A comment may sit further left than the rules it heads (RFC 9271).
    let indent =
      lines.filter { line in
        line.contains { !$0.isWhitespace } && line.first { $0 != " " } != ";"
      }
      .map { $0.prefix { $0 == " " }.count }.min() ?? 0
    for line in lines {
      let unindented = line.dropFirst(min(indent, line.prefix { $0 == " " }.count))
      guard let content = withoutComment(unindented) else { return nil }
      guard content.contains(where: { !$0.isWhitespace }) else { continue }
      if content.first?.isWhitespace == true {
        guard current != nil else { return nil }
        current? += " " + content
      } else {
        guard finishRule() else { return nil }
        current = String(content)
      }
    }
    guard finishRule(), !rules.isEmpty else { return nil }
    return rules
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
    private var position = 0
    private var references: [String] = []
    private var usesGrammarSyntax = false

    init(_ source: String) {
      characters = Array(source)
    }

    /// `rulename defined-as elements`, and nothing after it.
    mutating func rule() -> Rule? {
      guard let name = ruleName() else { return nil }
      skipSpace()
      guard take("=") else { return nil }
      let isIncremental = take("/")
      skipSpace()
      guard alternation() else { return nil }
      skipSpace()
      guard position == characters.count else { return nil }
      return Rule(
        name: name, isIncremental: isIncremental, references: references,
        usesGrammarSyntax: usesGrammarSyntax)
    }

    private var next: Character? {
      position < characters.count ? characters[position] : nil
    }

    private mutating func take(_ character: Character) -> Bool {
      guard next == character else { return false }
      position += 1
      return true
    }

    /// Takes the next character if it is one of `options`, compared without case: the
    /// letters after `%` may be written either way.
    private mutating func takeLetter(_ options: String) -> Character? {
      guard let next, options.contains(where: { $0 == Character(next.lowercased()) }) else {
        return nil
      }
      position += 1
      return Character(next.lowercased())
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
      while let next, next.isASCII, next.isLetter || next.isNumber || next == "-" {
        name.append(next)
        position += 1
      }
      return name
    }

    /// `concatenation *(*c-wsp "/" *c-wsp concatenation)`.
    private mutating func alternation() -> Bool {
      guard concatenation() else { return false }
      while true {
        let start = position
        skipSpace()
        guard take("/") else {
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
    /// A count directly before `x`, or before a name made only of hex digits, is a hex
    /// number, not a repetition: test vectors are valid ABNF by the letter, `4c0ffee`
    /// reading as four of a rule named `c0ffee` and `0x7` as none of `x7`.
    private mutating func repetition() -> Bool {
      var repeated = false
      var counted = false
      while let next, next.isASCII, next.isNumber {
        position += 1
        repeated = true
        counted = true
      }
      if take("*") || take("#") {
        repeated = true
        counted = false
        while let next, next.isASCII, next.isNumber { position += 1 }
      }
      if counted, startsHexNumber() { return false }
      if repeated { usesGrammarSyntax = true }
      return element()
    }

    /// Whether what follows a count reads as the rest of a hex number.
    private func startsHexNumber() -> Bool {
      guard let next else { return false }
      if next == "x" || next == "X" { return true }
      let name = characters[position...].prefix { $0.isASCII && ($0.isLetter || $0.isNumber) }
      return !name.isEmpty && name.allSatisfy(\.isHexDigit)
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
        return quotedLiteral()
      case "%":
        position += 1
        usesGrammarSyntax = true
        return numericOrCasedValue()
      case "<":
        return proseValue()
      default:
        guard let name = ruleName() else { return false }
        if !references.contains(name) { references.append(name) }
        return true
      }
    }

    private mutating func enclosedAlternation(closing: Character) -> Bool {
      skipSpace()
      guard alternation() else { return false }
      skipSpace()
      return take(closing)
    }

    /// `DQUOTE *(%x20-21 / %x23-7E) DQUOTE`.
    private mutating func quotedLiteral() -> Bool {
      guard take("\"") else { return false }
      while let next, next != "\"" {
        guard let value = next.asciiValue, (0x20...0x7E).contains(value) else { return false }
        position += 1
      }
      return take("\"")
    }

    /// `<` then printable characters but `>`, then `>`.
    private mutating func proseValue() -> Bool {
      guard take("<") else { return false }
      while let next, next != ">" {
        guard let value = next.asciiValue, (0x20...0x7E).contains(value) else { return false }
        position += 1
      }
      return take(">")
    }

    /// After `%`: `s` or `i` and a quoted literal (RFC 7405), or `x`, `d` or `b` and a
    /// number in that base, followed by `.`-joined numbers or one `-` range.
    private mutating func numericOrCasedValue() -> Bool {
      guard let base = takeLetter("sixdb") else { return false }
      if base == "s" || base == "i" { return quotedLiteral() }
      let digits: (Character) -> Bool =
        switch base {
        case "x": { $0.isHexDigit }
        case "d": { $0.isASCII && $0.isNumber }
        default: { $0 == "0" || $0 == "1" }
        }
      func number(_ parser: inout RuleParser) -> Bool {
        let start = parser.position
        while let next = parser.next, digits(next) { parser.position += 1 }
        return parser.position > start
      }
      guard number(&self) else { return false }
      if take("-") { return number(&self) }
      while take(".") {
        guard number(&self) else { return false }
      }
      return true
    }
  }
}
