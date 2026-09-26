import Foundation
import RFCKit

/// Which documents have a body in the app's on-disk cache.
///
/// The Downloaded filter asks for this on every filter change, and answering it
/// from the directory meant enumerating every file and parsing every name, each
/// time (#39). So the store scans once, the first time it is asked, and then
/// keeps this current itself: it inserts after each body it writes and removes
/// what it deletes. Nothing else writes to that directory.
///
/// Here rather than beside `DocumentStore` because the App target has no test
/// bundle, and which file names count as a cached body is exactly the kind of
/// rule that wants one.
public struct DocumentCacheIndex: Sendable {
  private var documents: Set<DocumentID>

  /// The formats the store writes bodies in. A file with any other extension is
  /// not a cached body, whatever its stem says.
  private static let bodyExtensions: Set<String> = [
    FileFormat.xml.pathExtension,
    FileFormat.text.pathExtension,
  ]

  /// Scans `directory` for the bodies the store has written there.
  ///
  /// A file counts only when its name is exactly what the store would have named
  /// it: a document's `fileStem` and a body format's extension. The RFC index
  /// lives in the same directory as `rfc-index.xml`, and a name the store did not
  /// write is not something it can answer for. A directory that cannot be read is
  /// an empty cache.
  public init(scanning directory: URL) {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    var documents: Set<DocumentID> = []
    for name in names {
      let url = URL(filePath: name)
      guard Self.bodyExtensions.contains(url.pathExtension) else {
        continue
      }
      let stem = url.deletingPathExtension().lastPathComponent
      guard let id = DocumentID(parsing: stem), id.fileStem == stem else {
        continue
      }
      documents.insert(id)
    }
    self.documents = documents
  }

  public func contains(_ id: DocumentID) -> Bool {
    documents.contains(id)
  }

  /// Numbers of every RFC with a cached body. Documents in the other series are
  /// cached too, but the library lists RFCs.
  public var rfcNumbers: Set<Int> {
    Set(documents.filter { $0.series == .rfc }.map(\.number))
  }

  public mutating func insert(_ id: DocumentID) {
    documents.insert(id)
  }

  public mutating func remove(_ id: DocumentID) {
    documents.remove(id)
  }
}
