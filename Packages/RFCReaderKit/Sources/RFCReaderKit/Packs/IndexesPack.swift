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
  /// whose manifest lists no `CitationIndex.fileName`, or that `isReadable` refuses,
  /// such as one of another `IndexSchema.version`, is not one, so a pack installed
  /// before an app update changed the schema gives way to the update's bundled one.
  public static func preferred(
    bundled: InstalledPack?, installed: InstalledPack?,
    isReadable: (InstalledPack) -> Bool = { _ in true }
  ) -> InstalledPack? {
    func usable(_ pack: InstalledPack?) -> InstalledPack? {
      pack.flatMap { holdsDatabase($0) && isReadable($0) ? $0 : nil }
    }
    guard let installed = usable(installed) else { return usable(bundled) }
    guard let bundled = usable(bundled) else { return installed }
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

  private static func holdsDatabase(_ pack: InstalledPack) -> Bool {
    pack.manifest.files.contains { $0.path == CitationIndex.fileName }
  }
}
