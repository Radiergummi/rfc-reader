import Foundation

/// `manifest.json`: every file of a data pack, with its size and SHA-256, so the app
/// can verify what it downloaded. corpus-build writes it and the app reads it, so
/// both use this one type (#36).
///
/// A pack carries its own manifest at its root, listing its files by bare name
/// (`rfc1.xml`) but never itself, and the documents it leaves out on purpose.
///
/// No date: the same files and version give the same manifest, which is what lets a
/// rebuild be compared with the release it would replace.
public struct Manifest: Codable, Equatable, Sendable {
  public struct Entry: Codable, Equatable, Sendable {
    public var path: String
    public var bytes: Int
    /// Lowercase hex; see `Manifest.hex(_:)`.
    public var sha256: String

    public init(path: String, bytes: Int, sha256: String) {
      self.path = path
      self.bytes = bytes
      self.sha256 = sha256
    }
  }

  /// A document the pack leaves out on purpose, and why: the app learns it from the
  /// manifest rather than from the document's text, which may be offline (#316).
  public struct Skip: Codable, Equatable, Sendable {
    /// The document's file stem, `rfc1119`.
    public var document: String
    public var reason: SkipReason

    public init(document: String, reason: SkipReason) {
      self.document = document
      self.reason = reason
    }
  }

  /// Why a pack leaves a document out.
  public enum SkipReason: String, Codable, Sendable {
    /// The text only says where the RFC's PDF or PostScript original is: RFC 570,
    /// 1119, 1124, 1128, 1129 and 1131. Converted, it is a document with nothing in
    /// it, which the schema refuses for two of them and takes for the other four; a
    /// section saying where the original is would be words the RFC does not have.
    /// The app opens the original instead (`PublishedOriginal`, #207).
    case publishedOnlyAsPDF = "published-only-as-pdf"
  }

  /// The name a pack's manifest has at the pack's root.
  public static let fileName = "manifest.json"

  public var version: String
  public var files: [Entry]
  public var skipped: [Skip]

  public init(version: String, files: [Entry], skipped: [Skip] = []) {
    self.version = version
    self.files = files
    self.skipped = skipped
  }

  /// A digest as the manifest spells it: lowercase hex, two digits a byte, the way
  /// `shasum -a 256` prints it. The hashing itself is the caller's, because RFCKit
  /// has no cryptography of its own: swift-crypto in corpus-build, CryptoKit in the
  /// app.
  public static func hex(_ digest: some Sequence<UInt8>) -> String {
    digest.map { byte in
      let digits = String(byte, radix: 16)
      return byte < 0x10 ? "0" + digits : digits
    }.joined()
  }
}
