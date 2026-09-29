import Crypto
import Foundation
import RFCKit

extension Manifest.Entry {
  /// The entry for the file named `path` whose contents are `data`.
  public init(path: String, data: Data) {
    self.init(path: path, bytes: data.count, sha256: Manifest.hex(SHA256.hash(data: data)))
  }
}
