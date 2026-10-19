import Foundation
import RFCKit

/// The documents a search looks in before its query says otherwise (#713): all of
/// them, or only the current ones, and perhaps one stream. Settings sets it for new
/// tabs, the search field shows each part as a token, and removing one leaves it
/// out for that search.
///
/// Default filters under the query rather than terms in it: a query naming its own
/// `status:` or `stream:` wins (`leaving`), and the query the reader typed stays
/// exactly what the field holds.
public struct SearchScope: Hashable, Sendable {
  /// Only documents neither obsoleted nor Historic.
  public var currentOnly: Bool
  /// Only this stream's documents.
  public var stream: PublicationStream?

  public init(currentOnly: Bool = false, stream: PublicationStream? = nil) {
    self.currentOnly = currentOnly
    self.stream = stream
  }

  /// Whether it leaves nothing out.
  public var isEverything: Bool {
    !currentOnly && stream == nil
  }

  /// What of it is still in force under a query's `filters`: a `status:` naming
  /// statuses replaces "current only", and a `stream:` the stream. `status:current`
  /// names none, and leaves out only what "current only" already does.
  public func leaving(_ filters: SearchFilters) -> SearchScope {
    var scope = self
    if !filters.statuses.isEmpty { scope.currentOnly = false }
    if !filters.streams.isEmpty { scope.stream = nil }
    return scope
  }

  /// Whether `row` is in scope. A series row, a BCP or STD the reader keeps as
  /// itself, has no status or stream of its own to leave it out by.
  public func includes(_ row: LibraryRow) -> Bool {
    guard let rfc = row.rfc else { return true }
    if currentOnly, rfc.isObsolete || rfc.currentStatus == .historic { return false }
    if let stream, rfc.stream != stream { return false }
    return true
  }

  /// A part of the scope, which the search field shows as a token of its own.
  public enum Part: Hashable, Sendable {
    case currentOnly
    case stream
  }

  /// A token in the search field naming a part of the scope in force.
  public struct Token: Hashable, Sendable, Identifiable {
    public let part: Part
    public let label: String
    public var id: Part { part }
  }

  /// One token per part in force: "Current Only", then the stream.
  public func tokens(locale: Locale = .interface) -> [Token] {
    var tokens: [Token] = []
    if currentOnly {
      tokens.append(Token(part: .currentOnly, label: String(kit: "Current Only", locale: locale)))
    }
    if let stream {
      tokens.append(
        Token(part: .stream, label: String(kit: "Stream: \(stream.displayName)", locale: locale)))
    }
    return tokens
  }

  /// The scope without `part`, as removing its token leaves it.
  public func removing(_ part: Part) -> SearchScope {
    var scope = self
    switch part {
    case .currentOnly: scope.currentOnly = false
    case .stream: scope.stream = nil
    }
    return scope
  }
}
