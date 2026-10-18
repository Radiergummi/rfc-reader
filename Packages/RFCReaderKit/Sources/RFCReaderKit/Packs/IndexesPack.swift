import Foundation
import RFCKit

/// The `indexes` pack (#174): the corpus's index database, which the app ships in its
/// bundle (#738), and which a copy installed in the packs directory replaces when it
/// is a later build. Updates arrive with the app's; nothing downloads one yet, so an
/// installed copy is a developer's `-installIndexesPack`.
public enum IndexesPack {
  /// The pack's folder, in the app's resources and in the packs directory alike.
  public static let name = "indexes"

  /// The copy to read: the installed one when its version is later than the bundled
  /// one's, and otherwise the bundled one; either when it is the only one. A copy
  /// whose manifest lists no `CitationIndex.fileName` is not one.
  public static func preferred(bundled: InstalledPack?, installed: InstalledPack?)
    -> InstalledPack?
  {
    let bundled = bundled.flatMap(holdingDatabase)
    let installed = installed.flatMap(holdingDatabase)
    guard let bundled else { return installed }
    guard let installed else { return bundled }
    return isLater(installed.manifest.version, than: bundled.manifest.version)
      ? installed : bundled
  }

  /// Whether `version` is a later build than `other`, compared number by number, so
  /// `2026.10.1` follows both `2026.9` and `2026.10`. A version that is not a dated
  /// one, such as the `dev` a local `make corpus` writes, follows every dated one, so
  /// a pack a developer installed is the one read.
  public static func isLater(_ version: String, than other: String) -> Bool {
    version.compare(other, options: .numeric) == .orderedDescending
  }

  private static func holdingDatabase(_ pack: InstalledPack) -> InstalledPack? {
    pack.manifest.files.contains { $0.path == CitationIndex.fileName } ? pack : nil
  }
}
