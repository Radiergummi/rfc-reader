import Foundation

/// What was typed, matched against registry entries (#175).
///
/// A bare value (`425`, `0x3`, `Retry-After`) matches in every registry that has it,
/// since `70` is a TLS alert and an HTTP status alike; a qualifier in front
/// (`tls alert 70`, `http 425`) narrows it to one. A value or a name has to match
/// exactly, ignoring case. A number matches however many digits it is written with,
/// `0x3` is `0x03`, but only in its own base: QUIC's codes are hexadecimal, and
/// `quic 10` is not `0x0a`. A code inside an assigned range matches the range.
public enum RegistryLookup {
  /// The words that name a registry, longest first, so `http status` is read before
  /// `http`.
  private static let qualifiers: [(words: String, registries: Set<IANARegistry>)] = [
    ("http status", [.httpStatusCodes]),
    ("http field", [.httpFieldNames]),
    ("http header", [.httpFieldNames]),
    ("status", [.httpStatusCodes]),
    ("header", [.httpFieldNames]),
    ("field", [.httpFieldNames]),
    ("http", [.httpStatusCodes, .httpFieldNames]),
    ("tls alert", [.tlsAlerts]),
    ("alert", [.tlsAlerts]),
    ("tls", [.tlsAlerts]),
    ("quic error", [.quicTransportErrors]),
    ("quic", [.quicTransportErrors]),
    ("media type", [.mediaTypes]),
    ("mime type", [.mediaTypes]),
  ]

  /// The entries `query` names, in the order they are given.
  public static func matches(_ query: String, in entries: [RegistryEntry]) -> [RegistryEntry] {
    var term = query.trimmingCharacters(in: .whitespaces).lowercased()
    var registries = Set(IANARegistry.allCases)
    if let qualifier = qualifiers.first(where: { term.hasPrefix($0.words + " ") }) {
      registries = qualifier.registries
      term = term.dropFirst(qualifier.words.count).trimmingCharacters(in: .whitespaces)
    }
    guard !term.isEmpty else { return [] }
    let number = Self.number(term)
    return entries.filter { entry in
      guard registries.contains(entry.registry) else { return false }
      if entry.value.lowercased() == term || entry.name?.lowercased() == term { return true }
      guard let number, let codes = codes(entry.value.lowercased()) else { return false }
      return number.isHexadecimal == codes.isHexadecimal && codes.range.contains(number.value)
    }
  }

  private struct Number {
    var value: Int
    var isHexadecimal: Bool
  }

  /// A decimal or `0x` hexadecimal number, or nil for anything else.
  private static func number(_ text: String) -> Number? {
    if text.hasPrefix("0x") {
      // `Int(_:radix:)` takes a sign as well, and a code has none.
      let digits = text.dropFirst(2)
      guard digits.allSatisfy(\.isHexDigit) else { return nil }
      return Int(digits, radix: 16).map { Number(value: $0, isHexadecimal: true) }
    }
    guard !text.isEmpty, text.allSatisfy(\.isASCII), text.allSatisfy(\.isNumber) else {
      return nil
    }
    return Int(text).map { Number(value: $0, isHexadecimal: false) }
  }

  /// The codes a value stands for: one number, or an assigned range such as
  /// `0x0100-0x01ff`, both ends in one base.
  private static func codes(_ value: String) -> (range: ClosedRange<Int>, isHexadecimal: Bool)? {
    let ends = value.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
    guard (1...2).contains(ends.count) else { return nil }
    let numbers = ends.compactMap(number)
    guard numbers.count == ends.count, let low = numbers.first, let high = numbers.last,
      low.isHexadecimal == high.isHexadecimal, low.value <= high.value
    else { return nil }
    return (low.value...high.value, low.isHexadecimal)
  }
}
