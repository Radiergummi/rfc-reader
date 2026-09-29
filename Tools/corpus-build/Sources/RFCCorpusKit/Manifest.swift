import Crypto
import Foundation

/// `manifest.json`: every file of a data pack, with its size and SHA-256, so the app
/// can verify what it downloaded.
///
/// No date: the same files and version give the same manifest, which is what lets a
/// rebuild be compared with the release it would replace.
public struct Manifest: Codable, Sendable {
  public struct Entry: Codable, Sendable {
    public var path: String
    public var bytes: Int
    public var sha256: String

    /// The entry for the file named `path` whose contents are `data`.
    public init(path: String, data: Data) {
      self.path = path
      self.bytes = data.count
      self.sha256 = SHA256.hash(data: data).map { byte in
        let digits = String(byte, radix: 16)
        return byte < 0x10 ? "0" + digits : digits
      }.joined()
    }
  }

  public var version: String
  public var files: [Entry]

  public init(version: String, files: [Entry]) {
    self.version = version
    self.files = files
  }
}
