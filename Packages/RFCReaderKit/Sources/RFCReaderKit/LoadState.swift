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

  /// How long a reader on iOS has nothing to show before it says it is loading
  /// (#263). A document in the cache normally builds within it, so a reader pushed
  /// for a citation slides in with its text rather than after a flash of progress;
  /// one that has to be fetched says so a moment later.
  public static let progressDelay = Duration.milliseconds(400)

  /// Whether the reader says it is loading: while there is neither a build nor a
  /// failure to show, once `isDue`, which the delay passing since it began makes it.
  public func showsProgress(isDue: Bool) -> Bool {
    isDue && built == nil && failure == nil
  }

  /// How long a build waits before it starts.
  ///
  /// A rebuild costs the whole attributed string plus a full relayout — 650 ms on
  /// the largest documents in the library — so a column still being dragged for a
  /// document already on screen waits that long to settle, and the next change
  /// cancels it: the window's edge being dragged is a new column on every frame.
  ///
  /// Nothing else waits. The first build has nothing on screen to disturb, and the
  /// column is already known, so it is built once and built right. A column that
  /// changed in one step — a rotation — has nothing to settle either: waiting for
  /// it left artwork at the old column's width for a second after the text had
  /// reflowed. A restyle — the text size, links underlined — comes a step at a
  /// time: View ▸ Bigger and Smaller (#153) waited out the whole delay before
  /// starting a build of about 120 ms, measured on RFC 9110, so each step took most
  /// of a second to show. The Settings slider builds on each tick now too, off the
  /// main actor, and a tick that comes before the build under way is done replaces
  /// it.
  public func buildDelay(for change: ColumnChange) -> Duration {
    built != nil && change == .live ? .milliseconds(650) : .zero
  }
}

/// How the column a build is for differs from the one on screen.
public enum ColumnChange: Equatable, Sendable {
  /// The same column: the build is a restyle.
  case none
  /// A new column in one step, such as a rotation, or the first column there is.
  case discrete
  /// A new column while a resize is under way, such as a window edge being
  /// dragged, which will be another column a frame from now.
  case live

  /// `isLive` is whether a resize is under way that has not ended: the Mac's live
  /// resize, or on iOS anything but a size transition that is not interactive.
  public init(from built: CGFloat?, to column: CGFloat?, isLive: Bool) {
    if column == built {
      self = .none
    } else if built == nil || !isLive {
      self = .discrete
    } else {
      self = .live
    }
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
    /// Cellular data is turned off, for the app or while roaming: a setting to
    /// change (`FetchPolicy.PathStatus.cellularDenied`). iOS opens the app's page in
    /// Settings, which has its switch; roaming's is a level up, under Cellular.
    case cellularDenied
    /// A secure connection could not be made, as a network's login page or a proxy
    /// causes by answering in the RFC Editor's place.
    case secureConnection
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
      case .cellularDenied: "antenna.radiowaves.left.and.right.slash"
      case .secureConnection: "lock.trianglebadge.exclamationmark"
      case .notFound: "questionmark.folder"
      case .server: "exclamationmark.icloud"
      case .unreadable: "doc.badge.ellipsis"
      case .other: "exclamationmark.triangle"
      }
    }

    public func recoverySuggestion(
      for subject: Subject, locale: Locale = .interface
    ) -> String {
      switch (self, subject) {
      case (.offline, _):
        String(kit: "Check your internet connection, then try again.", locale: locale)
      case (.cellularDenied, _):
        String(
          kit: "Cellular data is turned off for this app, or roaming is. Turn it on in Settings, or connect to Wi-Fi.",
          locale: locale)
      case (.secureConnection, _):
        String(
          kit:
            "A secure connection couldn't be made. If this network has a login page, sign in, or check its proxy settings, then try again.",
          locale: locale)
      case (.notFound, .document):
        String(kit: "The RFC Editor doesn't have this document.", locale: locale)
      case (.notFound, .originalText):
        String(kit: "This RFC has no plain-text version.", locale: locale)
      case (.server, _):
        String(kit: "The RFC Editor isn't responding right now. Try again later.", locale: locale)
      case (.unreadable, _):
        String(
          kit: "This document couldn't be read. It may open on rfc-editor.org.", locale: locale)
      case (.other, _):
        String(kit: "Try again, or open the document on rfc-editor.org.", locale: locale)
      }
    }
  }

  public var kind: Kind {
    switch error {
    case let error as URLError:
      switch error.code {
      case .notConnectedToInternet, .networkConnectionLost:
        return .offline
      case .dataNotAllowed, .internationalRoamingOff:
        return .cellularDenied
      case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
        .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
        .clientCertificateRejected, .clientCertificateRequired:
        return .secureConnection
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
