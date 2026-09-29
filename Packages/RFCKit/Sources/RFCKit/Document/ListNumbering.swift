import Foundation

/// How a numbered list counts: the counter, the text around it, and the value of its
/// first item. `(a)`, `3)`, `iv.` and RFCXML's `type="(%c)" start="1"` are all one of
/// these, read once where the list is parsed; the serializer writes it back and the
/// reader renders it, so neither has to understand the other's spelling.
public struct ListNumbering: Sendable, Hashable, Codable {
  public enum Counter: Sendable, Hashable, Codable {
    case decimal
    case lowerAlpha
    case upperAlpha
    case lowerRoman
    case upperRoman
  }

  public var counter: Counter
  /// The text before the counter: `(` in `(a)`, `Step ` in `Step A:`.
  public var prefix: String
  /// The text after it: `.` in `1.`, `)` in `(a)`.
  public var suffix: String
  /// The first item's value, counted in the counter's own terms: 3 is `c`.
  public var start: Int

  public init(
    counter: Counter = .decimal, prefix: String = "", suffix: String = ".", start: Int = 1
  ) {
    self.counter = counter
    self.prefix = prefix
    self.suffix = suffix
    self.start = start
  }

  // MARK: RFCXML

  /// RFCXML's `<ol type>`, as xml2rfc reads it: a single character is the counter
  /// followed by a full stop, and anything longer is a template with one `%`
  /// specifier in it. A specifier this model has no counter for (xml2rfc's octal
  /// `%o` and hexadecimal `%x`) counts in decimal between the template's own
  /// punctuation; a type with no specifier at all is plain decimal.
  public init(type: String?, start: Int) {
    self.init(start: start)
    guard let type, !type.isEmpty else { return }
    if type.count == 1, let character = type.first {
      counter = Self.counter(forSpecifier: character) ?? .decimal
      return
    }
    guard let percent = type.firstIndex(of: "%"), percent != type.index(before: type.endIndex)
    else { return }
    counter = Self.counter(forSpecifier: type[type.index(after: percent)]) ?? .decimal
    prefix = String(type[..<percent])
    suffix = String(type[type.index(percent, offsetBy: 2)...])
  }

  /// The `<ol type>` that reads back as this numbering.
  public var type: String {
    if prefix.isEmpty, suffix == "." { return String(Self.typeCharacter(for: counter)) }
    return "\(prefix)%\(Self.specifier(for: counter))\(suffix)"
  }

  private static func counter(forSpecifier character: Character) -> Counter? {
    switch character {
    case "1", "d": .decimal
    case "a", "c": .lowerAlpha
    case "A", "C": .upperAlpha
    case "i": .lowerRoman
    case "I": .upperRoman
    default: nil
    }
  }

  private static func typeCharacter(for counter: Counter) -> Character {
    switch counter {
    case .decimal: "1"
    case .lowerAlpha: "a"
    case .upperAlpha: "A"
    case .lowerRoman: "i"
    case .upperRoman: "I"
    }
  }

  private static func specifier(for counter: Counter) -> Character {
    switch counter {
    case .decimal: "d"
    case .lowerAlpha: "c"
    case .upperAlpha: "C"
    case .lowerRoman: "i"
    case .upperRoman: "I"
    }
  }

  // MARK: A legacy marker

  /// The numbering a plain-text list's first marker starts: `(a)`, `3)`, `iv.`. A
  /// marker of `i`, `v` and `x` alone is read as a Roman numeral, which is what a
  /// list starting on one of them nearly always is; any other single letter is a
  /// letter. Nil for anything that is not a marker of that shape.
  public init?(marker: some StringProtocol) {
    var body = Substring(marker)
    var prefix = ""
    if body.first == "(" {
      prefix = "("
      body = body.dropFirst()
    }
    guard let last = body.last, last == "." || last == ")" else { return nil }
    body = body.dropLast()
    guard !body.isEmpty else { return nil }
    let suffix = String(last)
    if let value = Int(body) {
      self.init(prefix: prefix, suffix: suffix, start: value)
    } else if body.allSatisfy({ "ivx".contains($0) }), let value = Self.romanValue(body) {
      self.init(counter: .lowerRoman, prefix: prefix, suffix: suffix, start: value)
    } else if body.count == 1, let letter = body.first, let ascii = letter.asciiValue,
      ("a"..."z").contains(letter)
    {
      self.init(
        counter: .lowerAlpha, prefix: prefix, suffix: suffix,
        start: Int(ascii - UInt8(ascii: "a")) + 1)
    } else {
      return nil
    }
  }

  /// Whether a list numbered like this, as the first marker of a piece of plain
  /// text, carries on a list of `itemCount` items numbered as `previous`: whether
  /// its first marker is the one that list would draw next. A marker is read on its
  /// own, so `i.` after `h.` reads as a Roman one; drawn, the two agree.
  public func continues(_ previous: ListNumbering, itemCount: Int) -> Bool {
    marker(at: 0) == previous.marker(at: itemCount)
  }

  /// The value of a lowercase Roman numeral, or nil when `numeral` is not the
  /// canonical spelling of one (`iiii`, `vx`).
  private static func romanValue(_ numeral: Substring) -> Int? {
    var total = 0
    var previous = 0
    for character in numeral.reversed() {
      guard let value = romanDigits[character] else { return nil }
      total += value < previous ? -value : value
      previous = max(previous, value)
    }
    return roman(total) == String(numeral) ? total : nil
  }

  // MARK: Markers

  private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz")

  /// The value of each lowercase Roman digit.
  private static let romanDigits: [Character: Int] = [
    "i": 1, "v": 5, "x": 10, "l": 50, "c": 100, "d": 500, "m": 1000,
  ]

  /// Roman symbols from the largest down, subtractive pairs included.
  private static let romanSymbols: [(Int, String)] = [
    (1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"),
    (50, "l"), (40, "xl"), (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i"),
  ]

  /// The marker of the item at `index`, counting from `start`.
  public func marker(at index: Int) -> String {
    prefix + counterText(start + index) + suffix
  }

  /// The counter for `value`. Letters and numerals have no zero and no negatives,
  /// and Roman numerals stop at 3999, as xml2rfc's do; outside that the number is
  /// written in decimal rather than not at all.
  private func counterText(_ value: Int) -> String {
    switch counter {
    case .decimal:
      return String(value)
    case .lowerAlpha, .upperAlpha:
      guard value >= 1 else { return String(value) }
      let letters = Self.letters(value)
      return counter == .upperAlpha ? letters.uppercased() : letters
    case .lowerRoman, .upperRoman:
      guard (1...3999).contains(value) else { return String(value) }
      let numeral = Self.roman(value)
      return counter == .upperRoman ? numeral.uppercased() : numeral
    }
  }

  /// xml2rfc's `int2letter`: `value - 1` written in base 26 with `a` as the zero
  /// digit, so 26 is `z` and 27 is `ba`. Not the spreadsheet column's `aa`: the
  /// published RFCs are rendered by xml2rfc, and a reference to "item ba" has to
  /// find it.
  private static func letters(_ value: Int) -> String {
    var remaining = value - 1
    var result = String(alphabet[remaining % 26])
    remaining /= 26
    while remaining > 0 {
      result.insert(alphabet[remaining % 26], at: result.startIndex)
      remaining /= 26
    }
    return result
  }

  private static func roman(_ value: Int) -> String {
    var remaining = value
    var result = ""
    for (arabic, symbol) in romanSymbols {
      while remaining >= arabic {
        result += symbol
        remaining -= arabic
      }
    }
    return result
  }
}
