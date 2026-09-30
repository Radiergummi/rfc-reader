import Foundation
import RFCKit

/// Where the reader is with a document (#135): loading it, showing it, or failed to
/// load it.
///
/// One value rather than the four optionals it replaces — the document, its build,
/// its error and whether a fetch was under way — so a document beside an error, or
/// a build without the document it was made from, cannot be written down. The
/// transitions refuse what the reader could not mean: a build arriving for a
/// document no longer loaded, or a late failure over a document already on screen.
public struct LoadState {
  public enum Phase {
    case loading
    /// The document, and its build once there is one. A rebuild replaces the build
    /// and keeps the document.
    case loaded(RFCDocument, BuiltDocument?)
    case failed(LoadFailure)
  }

  public private(set) var phase = Phase.loading

  public init() {}

  public var isLoading: Bool {
    if case .loading = phase { return true }
    return false
  }

  public var document: RFCDocument? {
    if case .loaded(let document, _) = phase { return document }
    return nil
  }

  public var built: BuiltDocument? {
    if case .loaded(_, let built) = phase { return built }
    return nil
  }

  public var failure: LoadFailure? {
    if case .failed(let failure) = phase { return failure }
    return nil
  }

  /// Loading again, as Try Again does after a failure.
  public mutating func begin() {
    phase = .loading
  }

  /// The fetched document. Only while loading: a document on screen stays.
  public mutating func finish(_ document: RFCDocument) {
    guard isLoading else { return }
    phase = .loaded(document, nil)
  }

  /// A fetch that failed. Only while loading.
  public mutating func fail(_ error: any Error) {
    guard isLoading else { return }
    phase = .failed(LoadFailure(error: error))
  }

  /// A build of the document loaded, over the one before it. Dropped when there is
  /// no document to install it over.
  public mutating func install(_ built: BuiltDocument) {
    guard case .loaded(let document, _) = phase else { return }
    phase = .loaded(document, built)
  }

  /// How long a build waits before it starts.
  ///
  /// A rebuild costs the whole attributed string plus a full relayout — 650 ms on
  /// the largest documents in the library — so a change to a document already on
  /// screen waits that long to settle, and the next change cancels it: every further
  /// tick of the font-size slider or the window's edge. The first build does not
  /// wait: there is nothing on screen to disturb, and the column is already known,
  /// so it is built once and built right.
  public var buildDelay: Duration {
    buildDelay(settling: true)
  }

  /// The same, for a change that may still be `settling`: a slider or a window edge
  /// is, a choice made once from a menu (Show Source) is not, and builds at once.
  public func buildDelay(settling: Bool) -> Duration {
    built == nil || !settling ? .zero : .milliseconds(650)
  }
}

/// Whether a change to what a document is built from builds it again (#135).
///
/// The inputs are whatever the build depends on — size, measure, the column — and
/// generic so the rule is tested here, away from the SwiftUI types the reader's
/// own inputs carry.
public enum BuildRequest: Equatable {
  /// Build for the new inputs, canceling any build under way.
  case start
  /// Leave things as they are: the build under way, or on screen, is for these.
  case keep
  /// Cancel the build under way: the screen already shows these inputs.
  case cancel

  public static func decide<Inputs: Equatable>(
    _ inputs: Inputs, built: Inputs?, building: Inputs?
  ) -> BuildRequest {
    if inputs == building { return .keep }
    if inputs == built { return building == nil ? .keep : .cancel }
    return .start
  }
}

/// Why a document did not load: the error itself rather than its description, so
/// what the reader says about it can depend on what it was (#125).
public struct LoadFailure {
  public let error: any Error

  public init(error: any Error) {
    self.error = error
  }

  public var message: String { error.localizedDescription }

  /// What was being loaded: the document, or its original text, which has a
  /// not-found of its own.
  public enum Subject: Sendable {
    case document, originalText
  }

  /// What failed, as far as the reader can tell from the error.
  public enum Kind: Sendable, Hashable, CaseIterable {
    /// The device's own connection: nothing reached the network.
    case offline
    /// The RFC Editor has no such document.
    case notFound
    /// The server did not answer, answered with an error, or sent a web page where
    /// the document should be.
    case server
    /// The document is there, and this reader cannot read it.
    case unreadable
    case other

    public var symbol: String {
      switch self {
      case .offline: "wifi.exclamationmark"
      case .notFound: "questionmark.folder"
      case .server: "exclamationmark.icloud"
      case .unreadable: "doc.badge.ellipsis"
      case .other: "exclamationmark.triangle"
      }
    }

    public func recoverySuggestion(for subject: Subject) -> String {
      switch (self, subject) {
      case (.offline, _):
        "Check your internet connection, then try again."
      case (.notFound, .document):
        "The RFC Editor doesn't have this document."
      case (.notFound, .originalText):
        "This RFC has no plain-text version."
      case (.server, _):
        "The RFC Editor isn't responding right now. Try again later."
      case (.unreadable, _):
        "This document couldn't be read. It may open on rfc-editor.org."
      case (.other, _):
        "Try again, or open the document on rfc-editor.org."
      }
    }
  }

  public var kind: Kind {
    switch error {
    case let error as URLError:
      switch error.code {
      case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
        .internationalRoamingOff:
        return .offline
      case .timedOut, .cannotFindHost, .cannotConnectToHost:
        return .server
      default:
        return .other
      }
    case let error as RFCEditorClient.ClientError:
      switch error {
      case .notFound:
        return .notFound
      case .httpStatus(let status, _) where status == 429 || (500..<600).contains(status):
        return .server
      case .decoding:
        return .unreadable
      case .httpStatus, .invalidResponse:
        return .other
      }
    case RFCXMLParser.ParseError.notAnRFC(rootElement: "html"):
      return .server
    case is RFCXMLParser.ParseError:
      return .unreadable
    default:
      return .other
    }
  }
}
