import Foundation

/// `manifest.json`: every file of a data pack, with its size and SHA-256, so the app
/// can verify what it downloaded. corpus-build writes it and the app reads it, so
/// both use this one type (#36).
///
/// A pack carries its own manifest at its root, listing its files by bare name
/// (`rfc1.xml`), and never itself.
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

  /// The name a pack's manifest has at the pack's root.
  public static let fileName = "manifest.json"

  public var version: String
  public var generatedAt: String
  public var files: [Entry]

  public init(version: String, generatedAt: String, files: [Entry]) {
    self.version = version
    self.generatedAt = generatedAt
    self.files = files
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
