import Foundation

/// A regex state machine, as Pygments, Rouge and Chroma lex: named states, each an
/// ordered list of rules, starting in `root`. At each point the first rule of the
/// current state that matches there wins; it emits its kind, or a kind per capture
/// group, and may push a state or pop some.
///
/// Each state is compiled to one alternation, `(rule0)|(rule1)|…`, and searched
/// forward from the current position, so one search finds the next token and the
/// characters before it, which no rule matched. Those are `plain`, and lexing goes
/// on: the engine never fails, and a fragment — most of the code in RFCs — costs
/// nothing. A state other than the root that meets a character it cannot match has
/// lost its place, and at the next newline lexing starts again from the root, as
/// Pygments recovers, so one stray quote does not color the rest of a block.
///
/// Matching uses transparent and non-anchoring bounds, so a lookbehind or `\b` sees
/// the characters before the current position, as far back as `lookbehind`, and `^`
/// matches only where a line starts. Patterns compile with `anchorsMatchLines`, as
/// Pygments' and Chroma's do. A state that changes state is searched a window of
/// the text at a time (`WindowedText`), which finds what a search of all of it would.
public struct Lexer: Highlighter {
  public enum Transition: Sendable, Hashable {
    case push(String)
    /// Leaves this many states, never the root.
    case pop(Int)
  }

  /// What a rule emits for its match.
  public enum Emit: Sendable, Hashable {
    case kind(TokenKind)
    /// One kind per capture group, in order. Characters of the match outside every
    /// group are plain, and a group that matched nothing emits nothing.
    case groups([TokenKind])
  }

  public struct Rule: Sendable {
    public let pattern: String
    public let emit: Emit
    public let transition: Transition?

    public init(_ pattern: String, _ kind: TokenKind, _ transition: Transition? = nil) {
      self.pattern = pattern
      self.emit = .kind(kind)
      self.transition = transition
    }

    public init(_ pattern: String, groups: [TokenKind], _ transition: Transition? = nil) {
      self.pattern = pattern
      self.emit = .groups(groups)
      self.transition = transition
    }
  }

  public enum DefinitionError: Error, Hashable {
    case noRootState
    case unknownState(String)
    case invalidPattern(String)
    case groupCountMismatch(String)
    case nestedGroups(String)
    /// A state's rules are compiled into one alternation, which renumbers groups.
    case backreference(String)
    /// It could match nothing and stay where it is, forever.
    case matchesEmptyWithoutTransition(String)
  }

  /// A state, compiled: rule `i` is the capture group `groups[i]`, and its own
  /// groups follow it.
  struct CompiledState {
    let expression: NSRegularExpression
    let rules: [Rule]
    let groups: [Int]
    /// Whether any rule changes state. One that none does is never left, and is
    /// lexed in one pass over the matches rather than a search per token.
    var changesState: Bool { rules.contains { $0.transition != nil } }

    func rule(matching match: NSTextCheckingResult) -> (rule: Rule, group: Int)? {
      for (index, rule) in rules.enumerated()
      where match.range(at: groups[index]).location != NSNotFound {
        return (rule, groups[index])
      }
      return nil
    }
  }

  private let states: [String: CompiledState]
  private let root: CompiledState

  static let matching: NSRegularExpression.MatchingOptions = [
    .withTransparentBounds, .withoutAnchoringBounds,
  ]

  /// How many rules in a row may match nothing and only change state before a
  /// character is given up as plain: two states that hand over to each other on a
  /// lookahead would otherwise trade places forever.
  static let emptyStepLimit = 8

  /// How much of the text after the current position a search is first handed, in
  /// UTF-16 code units, and how much before it, for a lookbehind, `\b` and `^`.
  static let window = 128
  static let lookbehind = 128

  public init(
    states definitions: [String: [Rule]], options: NSRegularExpression.Options = []
  ) throws(DefinitionError) {
    let options = options.union(.anchorsMatchLines)
    var compiled: [String: CompiledState] = [:]
    for (name, rules) in definitions {
      var groups: [Int] = []
      var next = 1
      for rule in rules {
        groups.append(next)
        next += 1 + (try Self.validate(rule, options: options, states: definitions))
      }
      let alternation = rules.map { "(\($0.pattern))" }.joined(separator: "|")
      let expression: NSRegularExpression
      do {
        expression = try NSRegularExpression(pattern: alternation, options: options)
      } catch {
        throw .invalidPattern(alternation)
      }
      compiled[name] = CompiledState(expression: expression, rules: rules, groups: groups)
    }
    guard let root = compiled["root"] else { throw .noRootState }
    self.states = compiled
    self.root = root
  }

  /// A lexer whose definition is part of the program: a definition error is a
  /// programmer's error, and the test that builds every lexer reports it with its
  /// reason first.
  static func defined(
    _ states: [String: [Rule]], options: NSRegularExpression.Options = []
  ) -> Lexer {
    do {
      return try Lexer(states: states, options: options)
    } catch {
      preconditionFailure("a lexer's definition is invalid: \(error)")
    }
  }

  /// A pattern that is part of the program, compiled once.
  static func expression(
    _ pattern: String, options: NSRegularExpression.Options = []
  ) -> NSRegularExpression {
    do {
      return try NSRegularExpression(pattern: pattern, options: options)
    } catch {
      preconditionFailure("\(pattern) does not compile: \(error)")
    }
  }

  /// Checks one rule, and returns how many capture groups it has.
  private static func validate(
    _ rule: Rule, options: NSRegularExpression.Options, states: [String: [Rule]]
  ) throws(DefinitionError) -> Int {
    let expression: NSRegularExpression
    do {
      expression = try NSRegularExpression(pattern: rule.pattern, options: options)
    } catch {
      throw .invalidPattern(rule.pattern)
    }
    if case .push(let target)? = rule.transition, states[target] == nil {
      throw .unknownState(target)
    }
    let shape = PatternShape(rule.pattern)
    if case .groups(let kinds) = rule.emit {
      guard kinds.count == expression.numberOfCaptureGroups else {
        throw .groupCountMismatch(rule.pattern)
      }
      if shape.hasNestedCaptureGroups { throw .nestedGroups(rule.pattern) }
    }
    if shape.hasBackreference { throw .backreference(rule.pattern) }
    let nothing = expression.firstMatch(in: "", range: NSRange(location: 0, length: 0))
    if rule.transition == nil, nothing != nil {
      throw .matchesEmptyWithoutTransition(rule.pattern)
    }
    return expression.numberOfCaptureGroups
  }

  public func tokens(in text: String) -> [SyntaxToken] {
    lex(text).tokens
  }

  /// `text`'s tokens, and how many UTF-16 code units the lexer handed its regular
  /// expressions to search: the work lexing does, which the tests bound.
  func lex(_ text: String) -> (tokens: [SyntaxToken], searched: Int) {
    let source = NSString(string: text)
    let length = source.length
    var output = TokenRun()
    var stack = ["root"]
    var position = 0
    var recovering = false
    var emptySteps = 0
    if !root.changesState {
      return (Self.tokens(in: text, length: length, state: root), length)
    }
    var windows = WindowedText(text)
    while position < length {
      let state = states[stack[stack.count - 1]] ?? root
      let match = windows.firstMatch(of: state.expression, from: position)
      let found = match?.range.location ?? length
      if found > position {
        // No rule matched these: plain. Inside a state, the state has lost its
        // place, and at a newline among them lexing starts again from the root.
        var gap = NSRange(location: position, length: found - position)
        var gaveUp = false
        if stack.count > 1 {
          recovering = true
          let newline = source.range(of: "\n", options: .literal, range: gap)
          if newline.location != NSNotFound {
            gap.length = NSMaxRange(newline) - position
            stack = ["root"]
            recovering = false
            gaveUp = true
          }
        }
        output.append(gap, .plain)
        position = NSMaxRange(gap)
        emptySteps = 0
        // The match was the lost state's: from the root, search again.
        if gaveUp || position < found { continue }
      }
      guard let match, let matched = state.rule(matching: match) else { break }
      if match.range.length == 0,
        matched.rule.transition == nil || emptySteps >= Self.emptyStepLimit
      {
        // Nothing can move lexing on here: one character is plain, if one is left.
        guard position < length else { break }
        let character = source.rangeOfComposedCharacterSequence(at: position)
        output.append(character, .plain)
        position = NSMaxRange(character)
        emptySteps = 0
        if stack.count > 1 { recovering = true }
        continue
      }
      Self.emit(match, rule: matched.rule, group: matched.group, into: &output)
      if let transition = matched.rule.transition {
        Self.apply(transition, to: &stack)
      }
      emptySteps = match.range.length == 0 ? emptySteps + 1 : 0
      position = NSMaxRange(match.range)
      if stack.count == 1 {
        recovering = false
      } else if recovering,
        source.range(of: "\n", options: .literal, range: match.range).location != NSNotFound
      {
        stack = ["root"]
        recovering = false
      }
    }
    return (output.tokens, windows.searched)
  }

  /// A state no rule leaves, lexed in one pass: what lies between two matches is
  /// plain, as in the loop above, and no rule can match nothing, since one that
  /// could and changes no state is refused when the lexer is built.
  private static func tokens(in text: String, length: Int, state: CompiledState) -> [SyntaxToken] {
    var output = TokenRun()
    var position = 0
    // `matches` rather than `enumerateMatches`, whose block takes an unsafe pointer.
    let matches = state.expression.matches(
      in: text, options: matching, range: NSRange(location: 0, length: length))
    for match in matches {
      guard let matched = state.rule(matching: match) else { continue }
      output.append(NSRange(location: position, length: match.range.location - position), .plain)
      emit(match, rule: matched.rule, group: matched.group, into: &output)
      position = NSMaxRange(match.range)
    }
    output.append(NSRange(location: position, length: length - position), .plain)
    return output.tokens
  }

  private static func emit(
    _ match: NSTextCheckingResult, rule: Rule, group: Int, into output: inout TokenRun
  ) {
    switch rule.emit {
    case .kind(let kind):
      output.append(match.range, kind)
    case .groups(let kinds):
      var cursor = match.range.location
      for (index, kind) in kinds.enumerated() {
        let range = match.range(at: group + 1 + index)
        // A group that matched nothing, or one inside a lookaround that reaches
        // outside the match, covers none of the match's characters.
        guard range.location != NSNotFound, range.location >= cursor,
          NSMaxRange(range) <= NSMaxRange(match.range)
        else { continue }
        output.append(NSRange(location: cursor, length: range.location - cursor), .plain)
        output.append(range, kind)
        cursor = NSMaxRange(range)
      }
      output.append(
        NSRange(location: cursor, length: NSMaxRange(match.range) - cursor), .plain)
    }
  }

  private static func apply(_ transition: Transition, to stack: inout [String]) {
    switch transition {
    case .push(let state):
      stack.append(state)
    case .pop(let depth):
      stack.removeLast(min(max(depth, 0), stack.count - 1))
    }
  }
}

/// A text searched a window at a time. `NSRegularExpression` takes a `String` and
/// hands ICU all of it on every search, which swift-corelibs-foundation copies to
/// UTF-16 each time, so a search per token over the whole text costs the square of
/// its length; the `XMLLexer` cases of `the work of lexing grows linearly with the
/// text` show it. A window from just before the position is enough wherever ICU
/// says more text could not have changed what it found (`hitEnd`, which covers
/// every attempt the search made, its lookaheads and a `$` included); where it
/// could, or nothing was found, the window doubles, until it reaches the end.
struct WindowedText {
  private let text: String
  private let length: Int
  /// How many code units the searches were handed, all told.
  private(set) var searched = 0

  init(_ text: String) {
    self.text = text
    self.length = text.utf16.count
  }

  /// The first match of `expression` at or after `position`, as a search of the
  /// whole text would find it, in the whole text's ranges.
  mutating func firstMatch(
    of expression: NSRegularExpression, from position: Int
  ) -> NSTextCheckingResult? {
    let start = boundary(max(0, position - Lexer.lookbehind))
    var size = Lexer.window
    while true {
      let end = boundary(min(length, position + size))
      // Sliced rather than decoded from UTF-16, which costs many times more on
      // swift-corelibs-foundation.
      let window = String(text.unicodeScalars[start.index..<end.index])
      searched += end.offset - start.offset
      var match: NSTextCheckingResult?
      var hitEnd = false
      // Unsafe only in the pointer the block is handed to stop the search at its
      // first match, which it writes and does not keep.
      unsafe expression.enumerateMatches(
        in: window, options: Lexer.matching,
        range: NSRange(location: position - start.offset, length: end.offset - position)
      ) { result, flags, stop in
        match = result
        hitEnd = flags.contains(.hitEnd)
        unsafe stop.pointee = true
      }
      if end.offset == length || (match != nil && !hitEnd) {
        return match?.adjustingRanges(offset: start.offset)
      }
      size *= 2
    }
  }

  /// The UTF-16 offset `offset`, moved back off the second half of a surrogate
  /// pair, so a window never splits a character, and its index.
  private func boundary(_ offset: Int) -> (offset: Int, index: String.Index) {
    let index = String.Index(utf16Offset: offset, in: text)
    guard offset > 0, offset < length, UTF16.isTrailSurrogate(text.utf16[index]) else {
      return (offset, index)
    }
    return (offset - 1, String.Index(utf16Offset: offset - 1, in: text))
  }
}

/// What a rule's pattern is made of, as far as the engine depends on it, read by
/// hand because `NSRegularExpression` does not say: whether a capture group is
/// nested in another, which `Emit.groups` cannot attribute, and whether it
/// refers back to a group by number, which the alternation renumbers.
struct PatternShape {
  private(set) var hasNestedCaptureGroups = false
  private(set) var hasBackreference = false

  init(_ pattern: String) {
    let characters = Array(pattern)
    var open: [Bool] = []  // whether each open group captures
    var inClass = false
    var index = 0
    while index < characters.count {
      let character = characters[index]
      if character == "\\" {
        if !inClass, index + 1 < characters.count,
          let digit = characters[index + 1].wholeNumberValue, digit > 0
        {
          hasBackreference = true
        }
        index += 2
        continue
      }
      if inClass {
        if character == "]" { inClass = false }
      } else if character == "[" {
        inClass = true
      } else if character == "(" {
        // `(?` opens a group that does not capture, except `(?<name>`.
        let next = characters[(index + 1)...].prefix(3)
        let captures =
          !next.starts(with: "?")
          || (next.starts(with: "?<") && !next.starts(with: "?<=") && !next.starts(with: "?<!"))
        if captures, open.contains(true) { hasNestedCaptureGroups = true }
        open.append(captures)
      } else if character == ")" {
        _ = open.popLast()
      }
      index += 1
    }
  }
}
