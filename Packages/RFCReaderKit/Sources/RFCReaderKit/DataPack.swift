import AppleArchive
import CryptoKit
import Foundation
import RFCKit
import System

// A data pack, as the app installs and reads it (#36; docs/DATA_PIPELINE.md): the
// documents of one pack, such as `legacy-xml`, with the pack's own manifest at its
// root. corpus.yml ships it as an Apple Archive compressed with LZFSE, and the app
// unpacks it on install, because an archive has no random access and reading one
// document out of it would decode the stream up to that document on every open.

/// Whether a directory holds exactly what its manifest lists: every listed file,
/// at its size and SHA-256, and no other.
public enum PackVerification {
  public enum Failure: Equatable, Sendable, CustomStringConvertible {
    case missing(String)
    case wrongSize(String, expected: Int, found: Int)
    case wrongDigest(String)
    /// Listed, and a symbolic link rather than a file.
    case notAFile(String)
    case unlisted(String)

    public var description: String {
      switch self {
      case .missing(let path): "\(path) is missing"
      case .notAFile(let path): "\(path) is a link, not a file"
      case .wrongSize(let path, let expected, let found):
        "\(path) is \(found) bytes, not \(expected)"
      case .wrongDigest(let path): "\(path) does not match its SHA-256"
      case .unlisted(let path): "\(path) is not in the manifest"
      }
    }
  }

  /// Every way `directory` differs from `manifest`, listed files first in the
  /// manifest's order, then unlisted ones by name; empty when it verifies. The
  /// manifest itself is not a file it lists, and neither is a hidden file, which
  /// `corpus-build manifest` skips too — a folder copied in Finder gains a
  /// `.DS_Store`.
  public static func failures(in directory: URL, against manifest: Manifest) -> [Failure] {
    var failures: [Failure] = []
    for entry in manifest.files {
      let url = directory.appending(path: entry.path)
      // A symbolic link would be read through, and verify against whatever it
      // points at, outside the pack.
      if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
        failures.append(.notAFile(entry.path))
        continue
      }
      guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
        failures.append(.missing(entry.path))
        continue
      }
      if data.count != entry.bytes {
        failures.append(.wrongSize(entry.path, expected: entry.bytes, found: data.count))
      } else if Manifest.hex(SHA256.hash(data: data)) != entry.sha256 {
        failures.append(.wrongDigest(entry.path))
      }
    }
    let listed = Set(manifest.files.map(\.path))
    let unlisted = files(in: directory).filter { $0 != Manifest.fileName && !listed.contains($0) }
    failures += unlisted.sorted().map(Failure.unlisted)
    return failures
  }

  /// Everything under `directory` but its folders, by paths relative to it:
  /// regular files, and symbolic links, which a pack has none of.
  private static func files(in directory: URL) -> [String] {
    let root = directory.standardizedFileURL.path(percentEncoded: false)
    let prefix = root.hasSuffix("/") ? root : root + "/"
    guard
      let enumerator = FileManager.default.enumerator(
        at: directory, includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles])
    else { return [] }
    return enumerator.compactMap { item in
      guard let url = item as? URL,
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == false
      else { return nil }
      let path = url.standardizedFileURL.path(percentEncoded: false)
      return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }
  }
}

/// An installed pack: where it is, and what its manifest says is in it.
public struct InstalledPack: Sendable {
  public let directory: URL
  public let manifest: Manifest
  private let listed: Set<String>

  public init(directory: URL, manifest: Manifest) {
    self.directory = directory
    self.manifest = manifest
    listed = Set(manifest.files.map(\.path))
  }

  /// The pack in `directory`, read from its manifest. Not verified: that is
  /// `PackInstaller`'s job, once, before a pack is put in place.
  public init(contentsOf directory: URL) throws {
    let data = try Data(contentsOf: directory.appending(path: Manifest.fileName))
    self.init(directory: directory, manifest: try JSONDecoder().decode(Manifest.self, from: data))
  }

  /// The pack's XML for `id`, or nil when the pack does not list it. Named the
  /// way the store names its own cached bodies, `rfc9110.xml`. A series has no
  /// document of its own, so the pack never lists one.
  public func file(for id: DocumentID) -> URL? {
    guard id.series == .rfc else { return nil }
    let name = DocumentCacheIndex.fileName(for: id, format: .xml)
    return listed.contains(name) ? directory.appending(path: name) : nil
  }
}

/// Reading a pack's archive: what `aa archive -a lzfse -d <pack>` wrote.
public enum PackArchive {
  public struct Unreadable: Error, CustomStringConvertible {
    public let archive: URL
    public var description: String { "\(archive.lastPathComponent) is not an Apple Archive" }
  }

  /// Unpacks `archive` into `directory`, which must exist.
  public static func extract(_ archive: URL, into directory: URL) throws {
    guard
      let file = ArchiveByteStream.fileStream(
        path: FilePath(archive.path(percentEncoded: false)), mode: .readOnly, options: [],
        permissions: FilePermissions(rawValue: 0o644))
    else { throw Unreadable(archive: archive) }
    defer { try? file.close() }
    guard let decompressed = ArchiveByteStream.decompressionStream(readingFrom: file) else {
      throw Unreadable(archive: archive)
    }
    defer { try? decompressed.close() }
    guard let decoder = ArchiveStream.decodeStream(readingFrom: decompressed) else {
      throw Unreadable(archive: archive)
    }
    defer { try? decoder.close() }
    guard
      let extractor = ArchiveStream.extractStream(
        extractingTo: FilePath(directory.path(percentEncoded: false)),
        flags: [.ignoreOperationNotPermitted])
    else { throw Unreadable(archive: archive) }
    do {
      _ = try ArchiveStream.process(readingFrom: decoder, writingTo: extractor)
    } catch {
      try? extractor.close()
      throw error
    }
    // Closed here, not deferred: closing is where the last writes finish, and a
    // failure there — a full disk — is the error to report, not the files it left
    // short.
    try extractor.close()
  }
}

/// Installs a pack from an archive or an unpacked folder: staged beside the
/// installed packs, verified, and only then put in place, so a pack that fails
/// leaves the one before it untouched. One version is installed per name.
public enum PackInstaller {
  public struct VerificationFailed: Error, CustomStringConvertible {
    public let failures: [PackVerification.Failure]
    public var description: String {
      "The pack does not match its manifest: "
        + failures.map(\.description).joined(separator: "; ")
    }
  }

  /// Installs `source` as `packs/name` and returns it. A folder is copied, not
  /// moved; anything else is read as an archive.
  @discardableResult
  public static func install(_ source: URL, as name: String, in packs: URL) throws
    -> InstalledPack
  {
    let files = FileManager.default
    try files.createDirectory(at: packs, withIntermediateDirectories: true)
    // Hidden, and in the same volume as the destination, so the swap is a rename.
    let staging = packs.appending(
      path: ".staging-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? files.removeItem(at: staging) }
    if (try? source.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
      try files.copyItem(at: source, to: staging)
    } else {
      try files.createDirectory(at: staging, withIntermediateDirectories: true)
      try PackArchive.extract(source, into: staging)
    }
    let staged = try InstalledPack(contentsOf: staging)
    let failures = PackVerification.failures(in: staging, against: staged.manifest)
    guard failures.isEmpty else { throw VerificationFailed(failures: failures) }

    let destination = packs.appending(path: name, directoryHint: .isDirectory)
    if files.fileExists(atPath: destination.path(percentEncoded: false)) {
      _ = try files.replaceItemAt(destination, withItemAt: staging)
    } else {
      try files.moveItem(at: staging, to: destination)
    }
    return InstalledPack(directory: destination, manifest: staged.manifest)
  }
}
