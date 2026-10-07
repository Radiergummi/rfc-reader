import Foundation
import RFCKit

/// Where each document wanted offline stands, as `OfflineKeeper` last left it, for
/// Available Offline's rows (#358).
public struct OfflineStatus: Sendable, Hashable {
  /// The documents with a body in the kept tier.
  public var kept: Set<DocumentID> = []
  /// The documents with a download running for them, whoever started it.
  public var downloading: Set<DocumentID> = []
  /// The documents whose last fetch failed, until Retry or a new path.
  public var failed: Set<DocumentID> = []
  /// The documents owed a fetch the path does not allow now.
  public var waiting: Set<DocumentID> = []
  /// Why `waiting` waits.
  public var deferral: FetchPolicy.Reason?

  public init(
    kept: Set<DocumentID> = [], downloading: Set<DocumentID> = [],
    failed: Set<DocumentID> = [], waiting: Set<DocumentID> = [],
    deferral: FetchPolicy.Reason? = nil
  ) {
    self.kept = kept
    self.downloading = downloading
    self.failed = failed
    self.waiting = waiting
    self.deferral = deferral
  }

  /// What `id`'s row says, or nil when it says nothing: its body is kept, which is
  /// what the list promises, or the keeper has not yet looked at it.
  ///
  /// A body on disk wins over a download still running for it, which only replaces
  /// it, and a download running wins over a failure or a wait it has ended.
  public func state(of id: DocumentID) -> OfflineRowState? {
    if kept.contains(id) { return nil }
    if downloading.contains(id) { return .downloading }
    if failed.contains(id) { return .failed }
    if waiting.contains(id), let deferral { return .waiting(deferral) }
    return nil
  }
}

/// What a row in Available Offline says beside its document, when its body is not
/// on the device yet.
public enum OfflineRowState: Sendable, Hashable {
  case downloading
  /// The last fetch failed: the row offers Retry.
  case failed
  /// The fetch waits for a path the policy allows: the row offers Download Now.
  case waiting(FetchPolicy.Reason)

  /// The row's few words about it.
  public func description(locale: Locale = .interface) -> String {
    switch self {
    case .downloading: String(kit: "Downloading…", locale: locale)
    case .failed: String(kit: "Couldn't download", locale: locale)
    case .waiting(.offline): String(kit: "Waiting for a connection", locale: locale)
    case .waiting(.cellularDenied):
      String(kit: "Waiting: cellular data is off for this app", locale: locale)
    case .waiting(.lowDataMode): String(kit: "Waiting: Low Data Mode is on", locale: locale)
    case .waiting(.waitingForWiFi): String(kit: "Waiting for Wi-Fi", locale: locale)
    case .waiting(.lowPowerMode): String(kit: "Waiting: Low Power Mode is on", locale: locale)
    }
  }

  /// The button beside it, which fetches on any path, or nil when there is none.
  public func action(locale: Locale = .interface) -> String? {
    switch self {
    case .downloading: nil
    case .failed: String(kit: "Retry", locale: locale)
    case .waiting: String(kit: "Download Now", locale: locale)
    }
  }
}
