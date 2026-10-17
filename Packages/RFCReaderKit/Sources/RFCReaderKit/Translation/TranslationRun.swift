import Foundation
import RFCKit

/// Where a translation of the document stands in a reader (#749).
public enum TranslationPhase: Equatable, Sendable {
  case idle
  /// The share of what had to be asked for that has come back.
  case translating(progress: Double)
  case translated(TranslatedDocument)
  case failed

  /// The translation, once it is made.
  public var translated: TranslatedDocument? {
    if case .translated(let translated) = self { return translated }
    return nil
  }

  /// Whether a translation is made or under way, so none is started: one that is
  /// idle or failed may be.
  public var isUnderWayOrMade: Bool {
    switch self {
    case .translating, .translated: true
    case .idle, .failed: false
    }
  }
}

/// What the document's header says of a translation the reader asked for: how far it
/// is, that the text is a machine's, or that it failed.
public enum TranslationMark: Equatable, Sendable {
  case translating(progress: Double)
  case translated
  case failed

  /// Nil while the reader shows the English. A translation that is made is still
  /// "translating" until the build on screen is the translated one.
  public init?(_ phase: TranslationPhase, showsTranslation: Bool, buildIsTranslation: Bool) {
    guard showsTranslation else { return nil }
    switch phase {
    case .idle: self = .translating(progress: 0)
    case .translating(let progress): self = .translating(progress: progress)
    case .translated: self = buildIsTranslation ? .translated : .translating(progress: 1)
    case .failed: self = .failed
    }
  }
}

/// One batch of a translation: what was asked for, and what has come back of it.
/// Each request is identified by its index, so a response is matched to its source
/// whatever the framework makes of the text's white space.
public struct TranslationRun: Sendable {
  public let requests: [String]
  public private(set) var received: [String: String] = [:]

  public init(_ requests: [String]) {
    self.requests = requests
  }

  /// Whether every request has come back: a batch that ended early, canceled, is a
  /// translation with English left in it.
  public var isComplete: Bool { received.count == requests.count }

  public var progress: Double {
    requests.isEmpty ? 1 : Double(received.count) / Double(requests.count)
  }

  /// Records the response identified by `identifier`. True where the progress has
  /// moved by a step worth showing, so the header is not hosted again for every
  /// paragraph.
  public mutating func receive(_ translation: String, for identifier: String?) -> Bool {
    guard let index = identifier.flatMap(Int.init), requests.indices.contains(index) else {
      return false
    }
    received[requests[index]] = translation
    return received.count.isMultiple(of: Self.step) || isComplete
  }

  static let step = 50
}

extension DocumentTranslation {
  /// The language a document is translated into: the first of `languages`, the
  /// reader's in order of preference, that is not English, which the RFCs already
  /// are. Nil for a reader who reads only English, who is not offered a translation.
  public static func target(preferring languages: [String]) -> Locale.Language? {
    languages.lazy
      .map { Locale.Language(identifier: $0) }
      .first { $0.languageCode != .english }
  }

  /// `target(preferring:)` the reader's own languages.
  public static var target: Locale.Language? {
    target(preferring: Locale.preferredLanguages)
  }
}
