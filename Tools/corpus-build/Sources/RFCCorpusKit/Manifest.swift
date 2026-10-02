import Crypto
import Foundation
import RFCKit

extension Manifest.Entry {
  /// The entry for the file named `path` whose contents are `data`.
  public init(path: String, data: Data) {
    self.init(path: path, bytes: data.count, sha256: Manifest.hex(SHA256.hash(data: data)))
  }
}

extension Manifest {
  /// The documents a convert run's `report.json` skipped, in its order: what the
  /// legacy pack's manifest lists beside its files (#316).
  public static func skips(inReport data: Data) throws -> [Skip] {
    try JSONDecoder().decode([DocumentReport].self, from: data).compactMap { report in
      report.skipped.map { Skip(document: report.id, reason: $0) }
    }
  }
}
