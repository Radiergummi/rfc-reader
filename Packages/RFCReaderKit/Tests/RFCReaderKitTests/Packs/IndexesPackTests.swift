import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// Which copy of the `indexes` pack the app reads (#738): the bundled one, unless one
/// installed in the packs directory is a later dated build, or the app is a Debug
/// build, which reads an installed one whatever its version. The tests pass
/// `prefersInstalled` themselves, since they run as a Debug build.
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
    #expect(
      IndexesPack.preferred(bundled: bundled, installed: nil, prefersInstalled: false)?.directory
        == bundled.directory)
  }

  @Test func `an installed pack is read when nothing is bundled`() {
    let installed = Self.pack("/packs/indexes", version: "2026.09")
    #expect(
      IndexesPack.preferred(bundled: nil, installed: installed, prefersInstalled: false)?.directory
        == installed.directory)
  }

  @Test func `a later installed pack replaces the bundled one`() {
    let installed = Self.pack("/packs/indexes", version: "2026.10.2")
    #expect(
      IndexesPack.preferred(bundled: bundled, installed: installed, prefersInstalled: false)?
        .directory
        == installed.directory)
  }

  /// An app update brings a later pack than the one a developer installed months ago.
  @Test func `an earlier or the same installed pack leaves the bundled one`() {
    for version in ["2026.10.1", "2026.10", "2026.9.4"] {
      let installed = Self.pack("/packs/indexes", version: version)
      #expect(
        IndexesPack.preferred(bundled: bundled, installed: installed, prefersInstalled: false)?
          .directory
          == bundled.directory, "\(version)")
    }
  }

  @Test func `a copy listing no database is passed over`() {
    let installed = Self.pack("/packs/indexes", version: "2027.01.1", files: ["other.sqlite"])
    #expect(
      IndexesPack.preferred(bundled: bundled, installed: installed, prefersInstalled: false)?
        .directory == bundled.directory)
    #expect(
      IndexesPack.preferred(
        bundled: Self.pack("/b", version: "1", files: []), installed: nil, prefersInstalled: false)
        == nil)
  }

  /// A copy this build cannot read, such as one of another schema, is passed over,
  /// whichever is later.
  @Test func `a copy that is not readable is passed over`() {
    let installed = Self.pack("/packs/indexes", version: "dev")
    let notInstalled = { (pack: InstalledPack) in pack.directory != installed.directory }
    #expect(
      IndexesPack.preferred(
        bundled: bundled, installed: installed, prefersInstalled: true, isReadable: notInstalled)?
        .directory == bundled.directory)
    #expect(
      IndexesPack.preferred(
        bundled: nil, installed: installed, prefersInstalled: true, isReadable: notInstalled) == nil
    )
  }

  @Test func `versions compare number by number`() {
    #expect(IndexesPack.isLater("2026.10.1", than: "2026.9"))
    #expect(IndexesPack.isLater("2026.10.1", than: "2026.10"))
    #expect(IndexesPack.isLater("2026.10.10", than: "2026.10.9"))
    #expect(!IndexesPack.isLater("2026.10.1", than: "2026.10.1"))
    #expect(!IndexesPack.isLater("2026.9.9", than: "2026.10.1"))
  }

  /// `make corpus` writes `dev` unless told a version, which says nothing of when it
  /// was built: a Release build never takes it for a later one, so a pack a Debug build
  /// installed months ago cannot hide the bundled packs of every update since.
  @Test func `an undated version is never later`() {
    #expect(!IndexesPack.isLater("dev", than: "2026.10.1"))
    #expect(!IndexesPack.isLater("2026.10.1", than: "dev"))
    let installed = Self.pack("/packs/indexes", version: "dev")
    #expect(
      IndexesPack.preferred(bundled: bundled, installed: installed, prefersInstalled: false)?
        .directory == bundled.directory)
  }

  /// A developer who installed a pack, a locally built one or an earlier one, meant to
  /// read it.
  @Test func `a Debug build reads an installed pack whatever its version`() {
    for version in ["dev", "2026.09", "2026.10.1"] {
      let installed = Self.pack("/packs/indexes", version: version)
      #expect(
        IndexesPack.preferred(bundled: bundled, installed: installed, prefersInstalled: true)?
          .directory == installed.directory, "\(version)")
    }
  }
}
