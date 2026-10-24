import Foundation

/// Identifies an Internet-Draft, and optionally one of its revisions:
/// `draft-ietf-httpbis-semantics-19`, or `draft-ietf-httpbis-semantics` for whichever
/// revision is the newest.
///
/// A type of its own rather than a series of `DocumentID`, which is a series and a
/// number, and which the index, citations, the library and user data all take to
/// have one (decision on #734). A draft is named, not numbered, and is never in the
/// RFC index.
public struct DraftID: Hashable, Sendable, Codable, CustomStringConvertible {
  /// The draft's name, without its revision: `draft-ietf-httpbis-semantics`.
  public let name: String
  /// The revision, two digits from `00`; nil for the newest, whichever that is.
  public let revision: String?

  /// Nil when `name` is not a draft's name, or `revision` is not two digits.
  public init?(name: String, revision: String? = nil) {
    guard Self.isName(name), revision.map(Self.isRevision) ?? true else { return nil }
    self.name = name
    self.revision = revision
  }

  /// A draft's name, with or without its revision, as people type and link it:
  /// `draft-ietf-httpbis-semantics-19`, `Draft-IETF-HTTPbis-Semantics`. A last part
  /// of two digits is the revision, as the IETF's naming rules have it.
  public init?(parsing input: String) {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let parts = trimmed.split(separator: "-", omittingEmptySubsequences: false)
    if let last = parts.last, Self.isRevision(String(last)), parts.count > 2 {
      self.init(name: parts.dropLast().joined(separator: "-"), revision: String(last))
    } else {
      self.init(name: trimmed)
    }
  }

  /// The same draft at `revision`, or at its newest for nil.
  public func at(revision: String?) -> DraftID? {
    DraftID(name: name, revision: revision)
  }

  /// `draft-ietf-httpbis-semantics-19`, or the name alone for the newest: what the
  /// IETF's archive names a revision's files by, and the app's scheme its host.
  public var description: String {
    revision.map { "\(name)-\($0)" } ?? name
  }

  /// How the draft is named to a reader: the same as `description`, which is how
  /// the IETF writes it everywhere.
  public var displayName: String { description }

  /// The app's own URL for the draft: `rfc://draft-ietf-httpbis-semantics-19`, or
  /// without the revision for the newest (decision on #734). A draft's name always
  /// starts with `draft-`, so it never reads as an RFC number or a series.
  public var appURL: URL {
    appURL(fragment: nil)
  }

  /// `appURL` with `fragment`, percent-encoded through `URLComponents`.
  public func appURL(fragment: String?) -> URL {
    var components = URLComponents()
    components.scheme = RFCLink.scheme
    components.host = description
    components.fragment = fragment
    // Unwrapped because nothing here can fail: the host is a draft name's own
    // letters, digits and hyphens, and the fragment is percent-encoded.
    return components.url!
  }

  /// A draft's name: `draft-`, then two or more parts of lowercase letters and
  /// digits, separated by single hyphens, as the IETF's naming rules have it: its
  /// source and its subject at the least.
  private static func isName(_ name: String) -> Bool {
    let parts = name.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count >= 3, parts[0] == "draft" else { return false }
    return parts.dropFirst().allSatisfy { part in
      !part.isEmpty && part.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) }
    }
  }

  private static func isRevision(_ revision: String) -> Bool {
    revision.count == 2 && revision.allSatisfy { $0.isASCII && $0.isNumber }
  }
}

/// What the reader can open: a document of the RFC Editor's series, or an
/// Internet-Draft (#728). Where the reader, its history and its cache take either;
/// everything that only an RFC has, its index entry, its bookmark, its errata, keeps
/// taking a `DocumentID`.
public enum ReadableDocument: Hashable, Sendable, Codable, CustomStringConvertible {
  case rfc(DocumentID)
  case draft(DraftID)

  /// The RFC, BCP, STD or FYI, if this is one.
  public var rfc: DocumentID? {
    if case .rfc(let id) = self { id } else { nil }
  }

  /// The draft, if this is one.
  public var draft: DraftID? {
    if case .draft(let id) = self { id } else { nil }
  }

  /// `RFC9110`, or the draft's name with its revision.
  public var description: String {
    switch self {
    case .rfc(let id): id.description
    case .draft(let id): id.description
    }
  }

  /// `RFC 9110`, or the draft's name with its revision.
  public var displayName: String {
    switch self {
    case .rfc(let id): id.displayName
    case .draft(let id): id.displayName
    }
  }
}
