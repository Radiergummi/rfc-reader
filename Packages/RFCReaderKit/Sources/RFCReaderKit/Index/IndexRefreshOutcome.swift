import Foundation
import RFCKit

/// What a refresh of the index does with the RFC Editor's answer (#314).
public enum IndexRefreshOutcome: Equatable, Sendable {
  /// A `304` for the index kept: it is current as of now.
  case recordUnchanged(IndexCheck)
  /// A `304` with nothing kept, which sent no validators: there is no index to
  /// wait for.
  case settle
  /// A new index, parsed, kept and shown.
  case install(Data, validators: CacheValidators?)

  /// - Parameter kept: The check of the index kept, which a request sends the
  ///   validators of; nil when there is no index in memory.
  public init(_ fetched: IndexFetch, kept: IndexCheck?) {
    switch fetched {
    case .unchanged:
      self = kept.map { .recordUnchanged($0) } ?? .settle
    case .changed(let data, let validators):
      self = .install(data, validators: validators)
    }
  }
}
