import Foundation
import RFCKit

/// The converted corpus as `index`, `abbreviations` and `queries` read it: the `.xml`
/// files of a directory, in name order, each the document its file name names.
public struct ConvertedCorpus: Sendable {
  /// One file of the corpus.
  public struct File: Sendable {
    public var url: URL
    /// The document the file's name names, nil for one that names none, such as a copy
    /// of the RFC index. By the name, not the header: a converted header may lack its
    /// number, or state another one, and two files must not read as the same document.
    public var id: DocumentID?

    public var stem: String { url.deletingPathExtension().lastPathComponent }
  }

  /// What reading the corpus left out.
  public struct Reading {
    /// The files that name no document, which nothing reads.
    public var passedOver: [File] = []
    /// The files that name a document and do not parse, with why.
    public var unreadable: [(file: File, error: any Error)] = []
  }

  public var files: [File]

  /// The `.xml` files of `directory`, in name order.
  public init(directory: URL) throws {
    files = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "xml" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
    .map { File(url: $0, id: DocumentID(fileStem: $0.deletingPathExtension().lastPathComponent)) }
  }

  /// Parses every file that names a document, one at a time so the corpus is never
  /// held at once, and hands `body` each document that parses, with its file and that
  /// file's place among `files`. What it left out is the caller's to report.
  public func read(
    _ body: (_ offset: Int, _ file: URL, _ id: DocumentID, _ document: RFCDocument) throws -> Void
  ) throws -> Reading {
    var reading = Reading()
    for (offset, file) in files.enumerated() {
      guard let id = file.id else {
        reading.passedOver.append(file)
        continue
      }
      let document: RFCDocument
      do {
        document = try RFCXMLParser.parse(Data(contentsOf: file.url))
      } catch {
        reading.unreadable.append((file, error))
        continue
      }
      try body(offset, file.url, id, document)
    }
    return reading
  }
}
