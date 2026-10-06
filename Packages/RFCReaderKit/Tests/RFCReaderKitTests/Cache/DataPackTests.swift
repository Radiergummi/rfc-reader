import AppleArchive
import CryptoKit
import Foundation
import RFCKit
import System
import Testing

@testable import RFCReaderKit

/// A data pack as the app installs it (#36): an Apple Archive of documents and their
/// manifest, unpacked, verified file by file, and only then put in place. The packs
/// here are synthetic files, never RFC text.
@Suite("Data packs")
struct DataPackTests {
  /// A fresh directory, removed when the test's `Scratch` goes.
  final class Scratch {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "DataPackTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    init() throws {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }
  }

  private static let files: [String: String] = [
    "rfc1.xml": "<rfc>one</rfc>",
    "rfc2.xml": "<rfc>two, a little longer</rfc>",
  ]

  /// A pack directory holding `files` and a manifest that lists them.
  private func makePack(
    in parent: URL, named name: String = "pack", files: [String: String] = files
  )
    throws -> URL
  {
    let directory = parent.appending(path: name, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var entries: [Manifest.Entry] = []
    for (path, contents) in files.sorted(by: { $0.key < $1.key }) {
      let data = Data(contents.utf8)
      try data.write(to: directory.appending(path: path))
      entries.append(
        Manifest.Entry(path: path, bytes: data.count, sha256: Manifest.hex(SHA256.hash(data: data)))
      )
    }
    let manifest = Manifest(version: "2026.09", files: entries)
    try JSONEncoder().encode(manifest).write(to: directory.appending(path: Manifest.fileName))
    return directory
  }

  private func manifest(of directory: URL) throws -> Manifest {
    try JSONDecoder().decode(
      Manifest.self, from: Data(contentsOf: directory.appending(path: Manifest.fileName)))
  }

  /// `aa archive -a lzfse -d <directory> -o <archive>`, as corpus.yml builds a pack:
  /// the same fields as `aa`, owner and flags included, so extraction meets what a
  /// pack built on the runner carries.
  private func archive(_ directory: URL, to archive: URL) throws {
    let file = try #require(
      ArchiveByteStream.fileStream(
        path: FilePath(archive.path), mode: .writeOnly, options: [.create, .truncate],
        permissions: FilePermissions(rawValue: 0o644)))
    let compressed = try #require(
      ArchiveByteStream.compressionStream(using: .lzfse, writingTo: file))
    let encoder = try #require(ArchiveStream.encodeStream(writingTo: compressed))
    let keys = try #require(
      ArchiveHeader.FieldKeySet("TYP,PAT,LNK,DEV,DAT,UID,GID,MOD,FLG,MTM,BTM,CTM"))
    try encoder.writeDirectoryContents(archiveFrom: FilePath(directory.path), keySet: keys)
    try encoder.close()
    try compressed.close()
    try file.close()
  }

  // MARK: - Verification

  @Test func `a pack that matches its manifest verifies`() throws {
    let scratch = try Scratch()
    let pack = try makePack(in: scratch.url)
    #expect(PackVerification.failures(in: pack, against: try manifest(of: pack)).isEmpty)
  }

  @Test func `a file the manifest lists and the pack lacks is missing`() throws {
    let scratch = try Scratch()
    let pack = try makePack(in: scratch.url)
    try FileManager.default.removeItem(at: pack.appending(path: "rfc2.xml"))
    #expect(
      PackVerification.failures(in: pack, against: try manifest(of: pack)) == [.missing("rfc2.xml")]
    )
  }

  @Test func `a file of another size is the wrong size`() throws {
    let scratch = try Scratch()
    let pack = try makePack(in: scratch.url)
    try Data("<rfc>1</rfc>".utf8).write(to: pack.appending(path: "rfc1.xml"))
    #expect(
      PackVerification.failures(in: pack, against: try manifest(of: pack))
        == [.wrongSize("rfc1.xml", expected: 14, found: 12)])
  }

  /// The same size, so only the digest can tell.
  @Test func `a file of the same size and other contents has the wrong digest`() throws {
    let scratch = try Scratch()
    let pack = try makePack(in: scratch.url)
    try Data("<rfc>eno</rfc>".utf8).write(to: pack.appending(path: "rfc1.xml"))
    #expect(
      PackVerification.failures(in: pack, against: try manifest(of: pack))
        == [.wrongDigest("rfc1.xml")])
  }

  @Test func `a file the manifest does not list is unlisted`() throws {
    let scratch = try Scratch()
    let pack = try makePack(in: scratch.url)
    try Data("<rfc>three</rfc>".utf8).write(to: pack.appending(path: "rfc3.xml"))
    #expect(
      PackVerification.failures(in: pack, against: try manifest(of: pack)) == [
        .unlisted("rfc3.xml")
      ]
    )
  }

  /// Followed, a link would verify against whatever it points at, outside the pack.
  @Test func `a listed file that is a symbolic link is not a file of the pack`() throws {
    let scratch = try Scratch()
    let pack = try makePack(in: scratch.url)
    let outside = scratch.url.appending(path: "outside.xml")
    try FileManager.default.moveItem(at: pack.appending(path: "rfc1.xml"), to: outside)
    try FileManager.default.createSymbolicLink(
      at: pack.appending(path: "rfc1.xml"), withDestinationURL: outside)
    #expect(
      PackVerification.failures(in: pack, against: try manifest(of: pack)) == [
        .notAFile("rfc1.xml")
      ]
    )
  }

  @Test func `an unlisted symbolic link is unlisted`() throws {
    let scratch = try Scratch()
    let pack = try makePack(in: scratch.url)
    try FileManager.default.createSymbolicLink(
      at: pack.appending(path: "rfc3.xml"), withDestinationURL: pack.appending(path: "rfc1.xml"))
    #expect(
      PackVerification.failures(in: pack, against: try manifest(of: pack)) == [
        .unlisted("rfc3.xml")
      ]
    )
  }

  // MARK: - Lookup

  @Test func `an RFC the pack lists is read from the pack`() throws {
    let scratch = try Scratch()
    let pack = try InstalledPack(contentsOf: try makePack(in: scratch.url))
    #expect(pack.file(for: .rfc(2)) == pack.directory.appending(path: "rfc2.xml"))
  }

  @Test func `an RFC the pack does not list is not in it`() throws {
    let scratch = try Scratch()
    let pack = try InstalledPack(contentsOf: try makePack(in: scratch.url))
    #expect(pack.file(for: .rfc(3)) == nil)
  }

  /// What the manifest says the pack leaves out because its text only points to its
  /// original (#316): not a file, so verification does not look for it.
  @Test func `a pack's pointers are the documents its manifest skips`() throws {
    let scratch = try Scratch()
    let directory = try makePack(in: scratch.url)
    var manifest = try manifest(of: directory)
    manifest.skipped = [Manifest.Skip(document: "rfc3", reason: .publishedOnlyAsPDF)]
    try JSONEncoder().encode(manifest).write(to: directory.appending(path: Manifest.fileName))
    #expect(PackVerification.failures(in: directory, against: manifest) == [])
    let pack = try InstalledPack(contentsOf: directory)
    #expect(pack.pointers == [.rfc(3)])
    #expect(pack.file(for: .rfc(3)) == nil)
  }

  /// A BCP is a series, not a document: its members are in the pack, it is not.
  @Test func `a series is not in the pack`() throws {
    let scratch = try Scratch()
    let pack = try InstalledPack(
      contentsOf: try makePack(in: scratch.url, files: ["bcp14.xml": "<rfc/>"]))
    #expect(pack.file(for: DocumentID(series: .bcp, number: 14)) == nil)
  }

  // MARK: - Archive and install

  @Test func `a pack survives the archive corpus yml writes`() throws {
    let scratch = try Scratch()
    let pack = try makePack(in: scratch.url)
    let aar = scratch.url.appending(path: "legacy-xml-2026.09.aar")
    try archive(pack, to: aar)
    let unpacked = scratch.url.appending(path: "unpacked", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)

    try PackArchive.extract(aar, into: unpacked)

    #expect(PackVerification.failures(in: unpacked, against: try manifest(of: pack)).isEmpty)
    #expect(
      try String(contentsOf: unpacked.appending(path: "rfc2.xml"), encoding: .utf8)
        == Self.files["rfc2.xml"])
  }

  @Test func `an archive installs as the named pack`() throws {
    let scratch = try Scratch()
    let aar = scratch.url.appending(path: "legacy-xml-2026.09.aar")
    try archive(try makePack(in: scratch.url), to: aar)
    let packs = scratch.url.appending(path: "Packs", directoryHint: .isDirectory)

    let installed = try PackInstaller.install(aar, as: "legacy-xml", in: packs)

    #expect(
      installed.directory.standardizedFileURL
        == packs.appending(path: "legacy-xml").standardizedFileURL)
    #expect(installed.file(for: .rfc(1)) != nil)
  }

  @Test func `a folder installs as the named pack`() throws {
    let scratch = try Scratch()
    let folder = try makePack(in: scratch.url)
    let packs = scratch.url.appending(path: "Packs", directoryHint: .isDirectory)

    let installed = try PackInstaller.install(folder, as: "legacy-xml", in: packs)

    #expect(installed.file(for: .rfc(2)) != nil)
    // Copied, not moved: the folder installed from is the developer's.
    #expect(FileManager.default.fileExists(atPath: folder.appending(path: "rfc2.xml").path))
  }

  /// Replaced only once the new one has verified.
  @Test func `a pack that fails to verify leaves the installed one in place`() throws {
    let scratch = try Scratch()
    let packs = scratch.url.appending(path: "Packs", directoryHint: .isDirectory)
    _ = try PackInstaller.install(try makePack(in: scratch.url), as: "legacy-xml", in: packs)
    let broken = try makePack(in: scratch.url, named: "broken", files: ["rfc9.xml": "<rfc/>"])
    try Data("tampered".utf8).write(to: broken.appending(path: "rfc9.xml"))

    #expect(throws: PackInstaller.VerificationFailed.self) {
      try PackInstaller.install(broken, as: "legacy-xml", in: packs)
    }

    let installed = try InstalledPack(contentsOf: packs.appending(path: "legacy-xml"))
    #expect(installed.file(for: .rfc(1)) != nil)
    #expect(installed.file(for: .rfc(9)) == nil)
    // Nothing staged is left behind either.
    #expect(try FileManager.default.contentsOfDirectory(atPath: packs.path) == ["legacy-xml"])
  }

  @Test func `a pack that verifies replaces the installed one`() throws {
    let scratch = try Scratch()
    let packs = scratch.url.appending(path: "Packs", directoryHint: .isDirectory)
    _ = try PackInstaller.install(try makePack(in: scratch.url), as: "legacy-xml", in: packs)
    let newer = try makePack(
      in: scratch.url, named: "newer", files: ["rfc9.xml": "<rfc>nine</rfc>"])

    try PackInstaller.install(newer, as: "legacy-xml", in: packs)

    let installed = try InstalledPack(contentsOf: packs.appending(path: "legacy-xml"))
    #expect(installed.file(for: .rfc(9)) != nil)
    #expect(installed.file(for: .rfc(1)) == nil)
    #expect(try FileManager.default.contentsOfDirectory(atPath: packs.path) == ["legacy-xml"])
  }

  /// Verification runs on a hidden staging folder, which must not hide what is in it.
  @Test func `an archive holding a file its manifest does not list is refused`() throws {
    let scratch = try Scratch()
    let pack = try makePack(in: scratch.url)
    try Data("<rfc>three</rfc>".utf8).write(to: pack.appending(path: "rfc3.xml"))
    let aar = scratch.url.appending(path: "legacy-xml-2026.09.aar")
    try archive(pack, to: aar)
    let packs = scratch.url.appending(path: "Packs", directoryHint: .isDirectory)

    #expect(throws: PackInstaller.VerificationFailed.self) {
      try PackInstaller.install(aar, as: "legacy-xml", in: packs)
    }
  }

  /// An install that was killed never ran its cleanup; the next one does it.
  @Test func `an install removes what an interrupted one left staged`() throws {
    let scratch = try Scratch()
    let packs = scratch.url.appending(path: "Packs", directoryHint: .isDirectory)
    let abandoned = packs.appending(path: ".staging-abandoned", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: abandoned, withIntermediateDirectories: true)

    try PackInstaller.install(try makePack(in: scratch.url), as: "legacy-xml", in: packs)

    #expect(try FileManager.default.contentsOfDirectory(atPath: packs.path) == ["legacy-xml"])
  }

  /// Downloaded again rather than restored from a backup.
  @Test func `the packs folder is excluded from backup`() throws {
    let scratch = try Scratch()
    let packs = scratch.url.appending(path: "Packs", directoryHint: .isDirectory)

    try PackInstaller.install(try makePack(in: scratch.url), as: "legacy-xml", in: packs)

    let values = try URL(filePath: packs.path).resourceValues(forKeys: [.isExcludedFromBackupKey])
    #expect(values.isExcludedFromBackup == true)
  }

  /// Installed from the folder it points at, not copied as a link.
  @Test func `a symbolic link to a folder installs the folder`() throws {
    let scratch = try Scratch()
    let folder = try makePack(in: scratch.url)
    let link = scratch.url.appending(path: "current")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
    let packs = scratch.url.appending(path: "Packs", directoryHint: .isDirectory)

    let installed = try PackInstaller.install(link, as: "legacy-xml", in: packs)

    #expect(installed.file(for: .rfc(2)) != nil)
  }

  /// Not "is not an Apple Archive": there is nothing there to be one.
  @Test func `a source that does not exist is reported as missing`() throws {
    let scratch = try Scratch()
    let packs = scratch.url.appending(path: "Packs", directoryHint: .isDirectory)

    #expect(throws: CocoaError.self) {
      try PackInstaller.install(
        scratch.url.appending(path: "absent.aar"), as: "legacy-xml", in: packs)
    }
  }

  /// Extraction writes before anything verifies, so an entry that would land outside
  /// the staging folder must be refused by the extraction itself.
  @Test(arguments: [
    [ArchiveEntry.file("../escaped.txt")],
    [ArchiveEntry.link("up", to: ".."), ArchiveEntry.file("up/escaped.txt")],
  ])
  func `an archive entry outside the pack is refused`(entries: [ArchiveEntry]) throws {
    let scratch = try Scratch()
    let aar = scratch.url.appending(path: "escape.aar")
    try archive(entries, to: aar)
    let staging = scratch.url.appending(path: "staging", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

    #expect(throws: (any Error).self) { try PackArchive.extract(aar, into: staging) }

    #expect(
      !FileManager.default.fileExists(atPath: scratch.url.appending(path: "escaped.txt").path))
  }

  /// One entry of a hand-made archive, for what `aa` would never write.
  struct ArchiveEntry: Sendable, CustomTestStringConvertible {
    let path: String
    let link: String?

    static func file(_ path: String) -> Self { Self(path: path, link: nil) }
    static func link(_ path: String, to target: String) -> Self { Self(path: path, link: target) }

    var testDescription: String { link.map { "\(path) -> \($0)" } ?? path }
  }

  private func archive(_ entries: [ArchiveEntry], to archive: URL) throws {
    let file = try #require(
      ArchiveByteStream.fileStream(
        path: FilePath(archive.path), mode: .writeOnly, options: [.create, .truncate],
        permissions: FilePermissions(rawValue: 0o644)))
    let compressed = try #require(
      ArchiveByteStream.compressionStream(using: .lzfse, writingTo: file))
    let encoder = try #require(ArchiveStream.encodeStream(writingTo: compressed))
    let contents = Array("escaped".utf8)
    for entry in entries {
      let header = ArchiveHeader()
      let type: ArchiveHeader.EntryType = entry.link == nil ? .regularFile : .link
      header.append(.uint(key: ArchiveHeader.FieldKey("TYP"), value: UInt64(type.rawValue)))
      header.append(.string(key: ArchiveHeader.FieldKey("PAT"), value: entry.path))
      header.append(.uint(key: ArchiveHeader.FieldKey("MOD"), value: 0o644))
      if let link = entry.link {
        header.append(.string(key: ArchiveHeader.FieldKey("LNK"), value: link))
      } else {
        header.append(.blob(key: ArchiveHeader.FieldKey("DAT"), size: UInt64(contents.count)))
      }
      try encoder.writeHeader(header)
      if entry.link == nil {
        try contents.withUnsafeBytes { bytes in
          try encoder.writeBlob(key: ArchiveHeader.FieldKey("DAT"), from: bytes)
        }
      }
    }
    try encoder.close()
    try compressed.close()
    try file.close()
  }

  // MARK: - Launch argument

  @Test func `a URL argument is downloaded from`() {
    #expect(
      PackInstaller.source(fromArgument: "http://127.0.0.1:8765/legacy-xml.aar")
        == URL(string: "http://127.0.0.1:8765/legacy-xml.aar"))
  }

  @Test func `a path argument is a file`() {
    #expect(
      PackInstaller.source(fromArgument: "/tmp/legacy xml.aar")
        == URL(filePath: "/tmp/legacy xml.aar"))
  }

  /// An app launched from the Finder or Xcode has no shell to expand it.
  @Test func `a tilde in a path argument is expanded`() {
    let source = PackInstaller.source(fromArgument: "~/legacy-xml.aar")
    #expect(source.isFileURL)
    #expect(!source.path(percentEncoded: false).contains("~"))
  }
}
