import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// Which copy of the `indexes` pack the app reads (#738): the bundled one, unless one
/// installed in the packs directory is a later build.
@Suite("Indexes pack")
struct IndexesPackTests {
  /// A pack at `path` whose manifest has `version` and lists `files`; nothing is read
  /// from the disk.
  private static func pack(
    _ path: String, version: String, files: [String] = [CitationIndex.fileName]
  ) -> InstalledPack {
    InstalledPack(
      directory: URL(fileURLWithPath: path, isDirectory: true),
      manifest: Manifest(
        version: version,
        files: files.map { Manifest.Entry(path: $0, bytes: 1, sha256: "00") }))
  }

  private let bundled = pack("/bundle/indexes", version: "2026.10.1")

  @Test func `the bundled pack is read when none is installed`() {
    #expect(IndexesPack.preferred(bundled: bundled, installed: nil)?.directory == bundled.directory)
  }

  @Test func `an installed pack is read when nothing is bundled`() {
    let installed = Self.pack("/packs/indexes", version: "2026.09")
    #expect(
      IndexesPack.preferred(bundled: nil, installed: installed)?.directory == installed.directory)
  }

  @Test func `a later installed pack replaces the bundled one`() {
    let installed = Self.pack("/packs/indexes", version: "2026.10.2")
    #expect(
      IndexesPack.preferred(bundled: bundled, installed: installed)?.directory
        == installed.directory)
  }

  /// An app update brings a later pack than the one a developer installed months ago.
  @Test func `an earlier or the same installed pack leaves the bundled one`() {
    for version in ["2026.10.1", "2026.10", "2026.9.4"] {
      let installed = Self.pack("/packs/indexes", version: version)
      #expect(
        IndexesPack.preferred(bundled: bundled, installed: installed)?.directory
          == bundled.directory, "\(version)")
    }
  }

  @Test func `a copy listing no database is passed over`() {
    let installed = Self.pack("/packs/indexes", version: "2027.01.1", files: ["other.sqlite"])
    #expect(
      IndexesPack.preferred(bundled: bundled, installed: installed)?.directory == bundled.directory)
    #expect(
      IndexesPack.preferred(bundled: Self.pack("/b", version: "1", files: []), installed: nil)
        == nil)
  }

  /// A copy this build cannot read, such as one of another schema, is passed over,
  /// whichever is later.
  @Test func `a copy that is not readable is passed over`() {
    let installed = Self.pack("/packs/indexes", version: "dev")
    let notInstalled = { (pack: InstalledPack) in pack.directory != installed.directory }
    #expect(
      IndexesPack.preferred(bundled: bundled, installed: installed, isReadable: notInstalled)?
        .directory == bundled.directory)
    #expect(
      IndexesPack.preferred(bundled: nil, installed: installed, isReadable: notInstalled) == nil)
  }

  @Test func `versions compare number by number`() {
    #expect(IndexesPack.isLater("2026.10.1", than: "2026.9"))
    #expect(IndexesPack.isLater("2026.10.1", than: "2026.10"))
    #expect(IndexesPack.isLater("2026.10.10", than: "2026.10.9"))
    #expect(!IndexesPack.isLater("2026.10.1", than: "2026.10.1"))
    #expect(!IndexesPack.isLater("2026.9.9", than: "2026.10.1"))
  }

  /// `make corpus` writes `dev` unless told a version: a pack a developer built and
  /// installed is the one they meant to read.
  @Test func `a locally built pack follows every dated one`() {
    #expect(IndexesPack.isLater("dev", than: "2026.10.1"))
  }
}
