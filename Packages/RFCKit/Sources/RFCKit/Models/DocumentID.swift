import Foundation

/// Identifies a document in one of the RFC Editor's series.
///
/// The canonical string form has no separator (`RFC9110`, `BCP14`, `STD3`), which is
/// how the RFC Editor's index refers to documents. RFC numbers passed 10000 in 2026,
/// so nothing here assumes a fixed digit count.
public struct DocumentID: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
  public enum Series: String, Sendable, Codable, CaseIterable, Comparable {
    case rfc = "RFC"
    case bcp = "BCP"
    case std = "STD"
    case fyi = "FYI"

    public static func < (lhs: Series, rhs: Series) -> Bool {
      lhs.sortOrder < rhs.sortOrder
    }

    private var sortOrder: Int {
      switch self {
      case .rfc: 0
      case .std: 1
      case .bcp: 2
      case .fyi: 3
      }
    }

    public var displayName: String {
      switch self {
      case .rfc: "RFC"
      case .bcp: "Best Current Practice"
      case .std: "Internet Standard"
      case .fyi: "For Your Information"
      }
    }
  }

  public let series: Series
  public let number: Int

  public init(series: Series, number: Int) {
    self.series = series
    self.number = number
  }

  public static func rfc(_ number: Int) -> DocumentID {
    DocumentID(series: .rfc, number: number)
  }

  /// The document a bibliography label names, when it names one: `RFC 2119`, `BCP14`.
  ///
  /// Stricter than `init(parsing:)` in one way. A bare number is an RFC number when a
  /// reader types it, but as a label it is only a position in the list: RFC 1004's
  /// `[2]` is the EGP specification, not RFC 2, and reading it as RFC 2 recorded 6,887
  /// entries in 1,381 converted documents as the RFC their number happened to be.
  public init?(label: String) {
    guard label.trimmingCharacters(in: .whitespaces).first?.isLetter == true else { return nil }
    self.init(parsing: label)
  }

  /// Parses loose user or document input such as `RFC9110`, `rfc 9110`, `RFC-9110`,
  /// `BCP 14`, or a bare number (which is treated as an RFC number).
  public init?(parsing input: String) {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    var seriesPart = ""
    var numberPart = ""
    for character in trimmed {
      if character.isLetter, numberPart.isEmpty {
        seriesPart.append(character)
      } else if character.isNumber {
        numberPart.append(character)
      } else if character == " " || character == "-" || character == "_" {
        if !numberPart.isEmpty { return nil }
      } else {
        return nil
      }
    }

    guard let number = Int(numberPart), number > 0 else { return nil }
    let series: Series
    if seriesPart.isEmpty {
      series = .rfc
    } else if let parsed = Series(rawValue: seriesPart.uppercased()) {
      series = parsed
    } else {
      return nil
    }
    self.init(series: series, number: number)
  }

  /// Canonical identifier without separator, e.g. `RFC9110`.
  public var description: String { "\(series.rawValue)\(number)" }

  /// Human-readable form, e.g. `RFC 9110`.
  public var displayName: String { "\(series.rawValue) \(number)" }

  /// The file-name stem the RFC Editor uses, e.g. `rfc9110`.
  public var fileStem: String { "\(series.rawValue.lowercased())\(number)" }

  public static func < (lhs: DocumentID, rhs: DocumentID) -> Bool {
    if lhs.series != rhs.series { return lhs.series < rhs.series }
    return lhs.number < rhs.number
  }
}
