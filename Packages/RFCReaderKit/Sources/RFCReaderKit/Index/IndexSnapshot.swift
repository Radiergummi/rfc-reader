import Foundation
import RFCKit

/// A decoded copy of the RFC index, kept in the app's caches so a launch reads it
/// instead of parsing 14 MB of XML.
///
/// JSON, because it was measured fastest of what Foundation offers: decoding the
/// whole index takes 149 ms, a binary property list 294 ms, and the XML parse it
/// replaces 452 ms (`make benchmark`, Release). The XML stays the source of truth:
/// a snapshot is only ever made from a parse of it, and one that cannot be trusted
/// is parsed around rather than repaired.
public enum IndexSnapshot {
  public static func encode(_ index: RFCIndex) throws -> Data {
    try JSONEncoder().encode(index)
  }

  public static func decode(_ data: Data) throws -> RFCIndex {
    try JSONDecoder().decode(RFCIndex.self, from: data)
  }

  /// Whether a snapshot written at `written` still describes the index.
  ///
  /// Not when the index is newer, which a refresh or a new bundled copy makes it.
  /// And not when the app is newer either: a snapshot is the model as the app that
  /// wrote it coded it, and a build that adds a field would otherwise decode the
  /// old snapshot without complaint and show the field empty until the index next
  /// changed. A new build costs one parse, the first time it launches.
  public static func isCurrent(written: Date?, index: Date, app: Date) -> Bool {
    guard let written else { return false }
    return written >= index && written >= app
  }
}
