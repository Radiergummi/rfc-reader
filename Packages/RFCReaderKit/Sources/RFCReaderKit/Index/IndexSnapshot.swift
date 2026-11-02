import Foundation
import RFCKit

/// A decoded copy of the RFC index, kept in the app's caches so a launch reads it
/// instead of parsing 14 MB of XML.
///
/// JSON, because it was measured fastest of what Foundation offers, ahead of a binary
/// property list (#405 has the comparison). The "Index: decode snapshot" and "Index:
/// parse" benchmarks of `make benchmark` measure it against the XML parse it
/// replaces. The XML stays the source of truth:
/// a snapshot is only ever made from a parse of it, and one that cannot be trusted
/// is parsed around rather than repaired.
public enum IndexSnapshot {
  public static func encode(_ index: RFCIndex) throws -> Data {
    try JSONEncoder().encode(index)
  }

  public static func decode(_ data: Data) throws -> RFCIndex {
    try JSONDecoder().decode(RFCIndex.self, from: data)
  }

  /// Whether a snapshot written at `written` still describes the index: not when the
  /// index is newer, which a refresh or a new bundled copy makes it.
  ///
  /// Whether the build reading it wrote it is the snapshot's name, `fileName(build:)`.
  public static func isCurrent(written: Date?, index: Date) -> Bool {
    guard let written else { return false }
    return written >= index
  }

  /// The name of the snapshot `build` writes and reads, `DocumentStore`'s build: a
  /// snapshot is the model as the build that wrote it coded it, and a build that adds
  /// a field would otherwise decode another's snapshot without complaint and show the
  /// field empty until the index next changed. Its own name rather than a comparison
  /// of dates, which trusted a snapshot newer than the app's executable, and an
  /// install whose executable keeps an older build date than that (#758). A new build
  /// costs one parse, the first time it launches.
  public static func fileName(build: String) -> String {
    let safe = String(build.map { $0.isLetter || $0.isNumber || $0 == "." ? $0 : "-" })
    return "\(prefix)\(safe).json"
  }

  private static let prefix = "rfc-index-snapshot-"
  /// What every build named its snapshot before `fileName(build:)`.
  private static let unkeyedName = "rfc-index.json"

  /// Whether `fileName` is a snapshot's, whichever build wrote it: what the store
  /// removes once its own build has written one.
  public static func isSnapshot(fileName: String) -> Bool {
    fileName == unkeyedName || (fileName.hasPrefix(prefix) && fileName.hasSuffix(".json"))
  }
}
