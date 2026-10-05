import Foundation
import RFCKit

/// Which documents have a body in the app's on-disk cache.
///
/// The Downloaded filter asks for this on every filter change, and answering it
/// from the directory meant enumerating every file and parsing every name, each
/// time (#39). So the store scans once, the first time it is asked, and then
/// keeps this current itself: every body it writes or deletes goes through
/// `update(_:by:)`, which records what is on disk for that one document afterwards.
///
/// The store is not the only thing that can change the directory — the system
/// purges Caches, and Finder will delete from either tier — so each question starts
/// with `revalidate()`, which compares the directory's modification date with the
/// one recorded when this last matched it and scans again only when they differ.
/// That is one `stat` per question instead of an enumeration, and a file removed
/// behind the app's back is gone from the Downloaded filter the next time it is
/// asked rather than at the next launch. A watcher would learn the same thing
/// sooner, at the price of a source to keep alive for a list nobody is looking at.
///
/// A type of its own rather than part of `DocumentStore`, because which file names
/// count as a cached body is exactly the kind of rule that wants tests of its own.
public struct DocumentCacheIndex: Sendable {
  private let directory: URL
  /// Every document with a body in the directory.
  public private(set) var documents: Set<DocumentID>

  /// The directory's modification date when `documents` last matched it, or `nil`
  /// when it could not be read.
  private var directoryDate: Date?

  /// The formats the store writes bodies in.
  public static let bodyFormats: [FileFormat] = [.xml, .text]

  /// A file with any other extension is not a cached body, whatever its stem says.
  private static let bodyExtensions = Set(bodyFormats.map(\.pathExtension))

  /// The name the store gives a document's body in `format`: the RFC Editor's own,
  /// `rfc9110.xml`.
  public static func fileName(for id: DocumentID, format: FileFormat) -> String {
    "\(id.fileStem).\(format.pathExtension)"
  }

  /// Scans `directory` for the bodies the store has written there.
  ///
  /// A file counts only when its name is exactly what the store would have named
  /// it: a document's `fileStem` and a body format's extension. The RFC index
  /// lives in the same directory as `rfc-index.xml`, and a name the store did not
  /// write is not something it can answer for. A directory that cannot be read is
  /// an empty cache.
  public init(scanning directory: URL) {
    let found = Self.scan(directory)
    self.directory = directory
    documents = found.documents
    directoryDate = found.date
  }

  public func contains(_ id: DocumentID) -> Bool {
    documents.contains(id)
  }

  /// Numbers of every RFC with a cached body. Documents in the other series are
  /// cached too, but the library lists RFCs.
  public var rfcNumbers: Set<Int> {
    Set(documents.filter { $0.series == .rfc }.map(\.number))
  }

  /// Scans again if something other than `update(_:by:)` has changed the directory
  /// since this last matched it. Ask before answering from the index.
  public mutating func revalidate() {
    guard Self.modificationDate(of: directory) != directoryDate else {
      return
    }
    let found = Self.scan(directory)
    documents = found.documents
    directoryDate = found.date
  }

  /// Runs `change`, which writes or deletes `id`'s bodies, and then records whether
  /// any of them is on disk.
  ///
  /// What is recorded is what the directory holds, not what `change` meant to do:
  /// a removal that fails on one format leaves the document cached, because a file
  /// the store cannot delete is still a file it will read. Revalidating first keeps
  /// a change made behind the store's back from being taken for the store's own
  /// when the directory's date is recorded afterwards.
  public mutating func update(_ id: DocumentID, by change: () throws -> Void) rethrows {
    revalidate()
    defer {
      let onDisk = Self.bodyFormats.contains { format in
        FileManager.default.fileExists(
          atPath: directory.appending(path: Self.fileName(for: id, format: format)).path)
      }
      if onDisk {
        documents.insert(id)
      } else {
        documents.remove(id)
      }
      directoryDate = Self.modificationDate(of: directory)
    }
    try change()
  }

  /// The date is read before the names, so a change made while they are read leaves
  /// the recorded date behind the directory's and the next question scans again.
  private static func scan(_ directory: URL) -> (documents: Set<DocumentID>, date: Date?) {
    let date = modificationDate(of: directory)
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    var documents: Set<DocumentID> = []
    for name in names {
      if let id = document(named: name) {
        documents.insert(id)
      }
    }
    return (documents, date)
  }

  /// The document a file in the cache is a body of, or nil when it is not one: its
  /// name must be exactly what the store would have written, a document's
  /// `fileStem` and a body format's extension.
  public static func document(named name: String) -> DocumentID? {
    let url = URL(filePath: name)
    guard bodyExtensions.contains(url.pathExtension) else {
      return nil
    }
    let stem = url.deletingPathExtension().lastPathComponent
    return DocumentID(fileStem: stem)
  }

  /// Asked of the file system on every call. `URL.resourceValues` may answer from
  /// values cached on the URL, and this one lives as long as the store.
  private static func modificationDate(of directory: URL) -> Date? {
    let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path)
    return attributes?[.modificationDate] as? Date
  }
}
