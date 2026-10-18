import CryptoKit
import Foundation

/// What an annotation is on (#522): a whole section, or a span of the model text from
/// one position to another, possibly across blocks, with the quote it covered, which
/// finds it again when the text moves (`Relocator`). The shape of the W3C Web
/// Annotation selectors: a position selector, with a text quote selector behind it.
public enum Target: Sendable, Hashable {
  case section(String)
  case range(start: Position, end: Position, quote: Quote)

  /// The span `range` of `model` covers, its start and end each under the innermost
  /// anchor that holds it. Nil for an empty range, or one no anchor holds.
  public init?(covering range: Range<Int>, in model: ModelText) {
    guard !range.isEmpty, let start = model.position(at: range.lowerBound, isEnd: false),
      let end = model.position(at: range.upperBound, isEnd: true)
    else { return nil }
    self = .range(start: start, end: end, quote: Quote(covering: range, in: model))
  }

  /// Where in `model` this target's stored positions are, without relocating it: nil
  /// when either anchor is gone, or the end does not come after the start.
  public func range(in model: ModelText) -> Range<Int>? {
    switch self {
    case .section(let anchor):
      return model.span(of: anchor)?.range
    case .range(let start, let end, _):
      guard let lower = model.offset(of: start), let upper = model.offset(of: end), lower < upper
      else { return nil }
      return lower..<upper
    }
  }
}

/// The text a target covered, as it was when the annotation was made: what relocation
/// looks for when the text at the stored position no longer matches.
///
/// A long quote keeps its first `exactLimit` characters, with the length and the
/// SHA-256 of the whole, so a highlight over a large figure stays small. The length and
/// the digest are of the whole covered text normalized (`TextNormalization`), as every
/// comparison is, so a change of white space alone does not detach it.
public struct Quote: Sendable, Hashable, Codable {
  /// The text covered, or its first `exactLimit` characters.
  public var exact: String
  /// Up to `contextLimit` characters before the start, and after the end.
  public var prefix: String
  public var suffix: String
  /// When `exact` was cut: the normalized length of the whole covered text, in UTF-16
  /// units, and its SHA-256 as hexadecimal.
  public var length: Int?
  public var digest: String?

  public static let exactLimit = 256
  public static let contextLimit = 32

  public init(exact: String, prefix: String, suffix: String, length: Int? = nil, digest: String? = nil) {
    self.exact = exact
    self.prefix = prefix
    self.suffix = suffix
    self.length = length
    self.digest = digest
  }

  public init(covering range: Range<Int>, in model: ModelText) {
    let covered = model.text(in: range)
    let before = model.text(in: max(0, range.lowerBound - Self.contextLimit * 2)..<range.lowerBound)
    let after = model.text(
      in: range.upperBound..<min(model.length, range.upperBound + Self.contextLimit * 2))
    prefix = String(before.suffix(Self.contextLimit))
    suffix = String(after.prefix(Self.contextLimit))
    if covered.count > Self.exactLimit {
      exact = String(covered.prefix(Self.exactLimit))
      let normalized = TextNormalization(Array(covered.utf16)).trimmed
      length = normalized.count
      digest = Self.digest(of: normalized)
    } else {
      exact = covered
      length = nil
      digest = nil
    }
  }

  /// Whether `exact` is all of the covered text.
  public var isCut: Bool { digest != nil }

  static func digest(of units: [UInt16]) -> String {
    let data = Data(String(decoding: units, as: UTF16.self).utf8)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

/// Where a target is now (#522).
public enum Relocation: Sendable, Hashable {
  /// Where it was stored. The target is the stored one, or the same span under a
  /// finer anchor that now holds it, which is written to the relocated fields as a
  /// moved one would be.
  case exact(Target)
  /// Found once, elsewhere.
  case moved(Target)
  /// Found more than once, at each of these raw ranges of the model text: drawn
  /// nowhere, since the code never guesses between them. The reader may choose one.
  case ambiguous([Range<Int>])
  /// Found nowhere. Kept, never deleted.
  case detached

  /// Whether it is where it was stored.
  public var isExact: Bool {
    if case .exact = self { true } else { false }
  }

  /// The target to draw, or nil for one that is drawn nowhere.
  public var target: Target? {
    switch self {
    case .exact(let target), .moved(let target): target
    case .ambiguous, .detached: nil
    }
  }
}

/// Finds targets again in a document's model text, which a pipeline change may have
/// moved: a heuristic fix, a block gaining an anchor, a document moving from converted
/// legacy text to authored XML. A pure function of the target and the text; it never
/// guesses between candidates by nearness.
public struct Relocator: Sendable {
  public let model: ModelText
  private let normalized: TextNormalization

  public init(_ model: ModelText) {
    self.model = model
    normalized = TextNormalization(model.units)
  }

  /// A quote of fewer characters than this must match both its prefix and its suffix.
  static let shortQuote = 12

  public func relocate(_ target: Target) -> Relocation {
    switch target {
    case .section(let anchor):
      return model.span(of: anchor) == nil ? .detached : .exact(target)
    case .range(let start, let end, let quote):
      if let range = target.range(in: model), matches(quote, at: range) {
        // The same text, re-expressed under the innermost anchors that hold it now.
        guard let current = Target(covering: range, in: model, quote: quote) else {
          return .exact(target)
        }
        return .exact(current)
      }
      let scopes = [
        model.span(of: start.anchor)?.range,
        model.offset(of: start).flatMap { model.section(containing: $0)?.range },
        model.span(of: end.anchor).flatMap { model.section(containing: $0.range.lowerBound)?.range },
        0..<model.length,
      ]
      var searched: Set<Range<Int>> = []
      for case let scope? in scopes where searched.insert(scope).inserted {
        let found = candidates(for: quote, startingIn: scope)
        if found.count == 1, let target = Target(covering: found[0], in: model, quote: quote) {
          return .moved(target)
        }
        if found.count > 1 { return .ambiguous(found) }
      }
      return .detached
    }
  }

  /// Whether the text at `range` is the quote's.
  private func matches(_ quote: Quote, at range: Range<Int>) -> Bool {
    let text = TextNormalization(Array(model.units[range])).trimmed
    if let digest = quote.digest {
      return text.count == quote.length && Quote.digest(of: text) == digest
    }
    return text == TextNormalization(Array(quote.exact.utf16)).trimmed
  }

  /// Every place the quote's text starts inside `scope`, with its context, as a raw
  /// range of the model text.
  func candidates(for quote: Quote, startingIn scope: Range<Int>) -> [Range<Int>] {
    let exact = TextNormalization(Array(quote.exact.utf16)).trimmed
    guard !exact.isEmpty else { return [] }
    let prefix = TextNormalization(Array(quote.prefix.utf16)).trimmed
    let suffix = TextNormalization(Array(quote.suffix.utf16)).trimmed
    let isShort = exact.count < Self.shortQuote
    let units = normalized.units
    var found: [Range<Int>] = []
    // The units come in the raw text's order, so the scope is one stretch of them.
    var index = normalized.start.partitioningIndex { $0 >= scope.lowerBound }
    while index + exact.count <= units.count, normalized.start[index] < scope.upperBound {
      defer { index += 1 }
      guard units[index] == exact[0], units[index..<index + exact.count].elementsEqual(exact)
      else { continue }
      // A cut quote runs on for its whole length, and must be the whole it was.
      let end = index + (quote.length ?? exact.count)
      guard end <= units.count else { continue }
      if let digest = quote.digest, Quote.digest(of: Array(units[index..<end])) != digest {
        continue
      }
      let before = trimmedEnd(units[max(0, index - prefix.count - 2)..<index])
      let after = trimmedStart(units[end..<min(units.count, end + suffix.count + 2)])
      let prefixMatches = before.suffix(prefix.count).elementsEqual(prefix)
      let suffixMatches = after.prefix(suffix.count).elementsEqual(suffix)
      guard isShort ? prefixMatches && suffixMatches : prefixMatches || suffixMatches else {
        continue
      }
      found.append(normalized.start[index]..<normalized.end[end - 1])
    }
    return found
  }

  private func trimmedEnd(_ units: ArraySlice<UInt16>) -> ArraySlice<UInt16> {
    var slice = units
    while slice.last == TextNormalization.space { slice = slice.dropLast() }
    return slice
  }

  private func trimmedStart(_ units: ArraySlice<UInt16>) -> ArraySlice<UInt16> {
    var slice = units
    while slice.first == TextNormalization.space { slice = slice.dropFirst() }
    return slice
  }
}

extension Target {
  /// The span `range` covers with a quote already taken: a relocated target keeps the
  /// quote it was made with.
  init?(covering range: Range<Int>, in model: ModelText, quote: Quote) {
    guard !range.isEmpty, let start = model.position(at: range.lowerBound, isEnd: false),
      let end = model.position(at: range.upperBound, isEnd: true)
    else { return nil }
    self = .range(start: start, end: end, quote: quote)
  }
}

/// Text as relocation compares it (#522): runs of white space collapse to one space,
/// soft hyphens and a line-end hyphenation go, and the spellings `[RFC2119]`,
/// `RFC 2119` and `RFC2119` are one. Each character kept remembers the raw characters
/// it came from, so what relocation returns is always a raw offset.
struct TextNormalization: Sendable {
  static let space: UInt16 = 0x20

  private(set) var units: [UInt16] = []
  /// For each unit, where the raw characters it came from start and end.
  private(set) var start: [Int] = []
  private(set) var end: [Int] = []

  init(_ raw: [UInt16]) {
    units.reserveCapacity(raw.count)
    var index = 0
    while index < raw.count {
      let unit = raw[index]
      if Self.isWhitespace(unit) {
        var stop = index + 1
        while stop < raw.count, Self.isWhitespace(raw[stop]) { stop += 1 }
        if units.last != Self.space { append(Self.space, from: index, to: stop) }
        index = stop
        continue
      }
      if unit == 0x00AD {
        index += 1
        continue
      }
      // A hyphen that ends a line between two letters joins them.
      if unit == 0x2D, let last = units.last, Self.isLetter(last) {
        var stop = index + 1
        var crossesLine = false
        while stop < raw.count, Self.isWhitespace(raw[stop]) {
          if raw[stop] == 0x0A { crossesLine = true }
          stop += 1
        }
        if crossesLine, stop < raw.count, Self.isLetter(raw[stop]) {
          index = stop
          continue
        }
      }
      if let reference = Self.reference(in: raw, at: index) {
        for (offset, character) in reference.units.enumerated() {
          let source = reference.sources[offset]
          append(character, from: source, to: source + 1)
        }
        index = reference.end
        continue
      }
      append(unit, from: index, to: index + 1)
      index += 1
    }
  }

  /// Without a space at either end.
  var trimmed: [UInt16] {
    var slice = units[...]
    while slice.first == Self.space { slice = slice.dropFirst() }
    while slice.last == Self.space { slice = slice.dropLast() }
    return Array(slice)
  }

  private mutating func append(_ unit: UInt16, from rawStart: Int, to rawEnd: Int) {
    units.append(unit)
    start.append(rawStart)
    end.append(rawEnd)
  }

  /// `RFC2119` for `[RFC2119]`, `RFC 2119` or `RFC2119` at `index`, with where each of
  /// its characters came from; nil anywhere else.
  private static func reference(in raw: [UInt16], at index: Int)
    -> (units: [UInt16], sources: [Int], end: Int)?
  {
    var cursor = index
    let opens = raw[cursor] == 0x5B
    if opens { cursor += 1 }
    let letters: [UInt16] = [0x52, 0x46, 0x43]  // RFC
    guard cursor + 3 <= raw.count, Array(raw[cursor..<cursor + 3]) == letters else { return nil }
    var units = letters
    var sources = [cursor, cursor + 1, cursor + 2]
    cursor += 3
    while cursor < raw.count, raw[cursor] == 0x20 || raw[cursor] == 0xA0 { cursor += 1 }
    let digitsStart = cursor
    while cursor < raw.count, (0x30...0x39).contains(raw[cursor]) {
      units.append(raw[cursor])
      sources.append(cursor)
      cursor += 1
    }
    guard cursor > digitsStart else { return nil }
    if opens {
      guard cursor < raw.count, raw[cursor] == 0x5D else { return nil }
      cursor += 1
    }
    return (units, sources, cursor)
  }

  private static func isWhitespace(_ unit: UInt16) -> Bool {
    switch unit {
    case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x2028, 0x2029: true
    default: false
    }
  }

  private static func isLetter(_ unit: UInt16) -> Bool {
    (0x41...0x5A).contains(unit) || (0x61...0x7A).contains(unit) || unit > 0x7F
      && Character(Unicode.Scalar(unit) ?? " ").isLetter
  }
}
