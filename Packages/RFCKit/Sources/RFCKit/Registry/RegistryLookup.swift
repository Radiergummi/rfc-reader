import Foundation

/// What was typed, matched against registry entries (#175).
///
/// A bare value (`425`, `0x3`, `Retry-After`) matches in every registry that has it,
/// since `70` is a TLS alert and an HTTP status alike; a qualifier in front
/// (`tls alert 70`, `http 425`) narrows it to one. A value or a name has to match
/// exactly, ignoring case, and a number matches however it is written: `0x3` is
/// `0x03`.
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
      return number != nil && Self.number(entry.value.lowercased()) == number
    }
  }

  /// A decimal or `0x` hexadecimal number, or nil for anything else.
  private static func number(_ text: String) -> Int? {
    if text.hasPrefix("0x") { return Int(text.dropFirst(2), radix: 16) }
    return text.allSatisfy(\.isNumber) ? Int(text) : nil
  }
}
