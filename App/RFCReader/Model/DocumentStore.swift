import Foundation
import RFCKit

/// On-disk cache of raw RFC files plus an in-memory cache of parsed documents.
///
/// Files are stored exactly as served by the RFC Editor, so the "original text"
/// view and re-parsing after a parser improvement both come for free.
actor DocumentStore {
  private let directory: URL
  private var parsed: [DocumentID: RFCDocument] = [:]

  init() {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
      0]
    directory = support.appending(path: "RFCReader", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  // MARK: - Index

  private var indexURL: URL { directory.appending(path: "rfc-index.xml") }

  func cachedIndex() throws -> (index: RFCIndex, updatedAt: Date)? {
    let url: URL
    var updatedAt = Date.distantPast
    if FileManager.default.fileExists(atPath: indexURL.path) {
      url = indexURL
      updatedAt =
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        ?? .distantPast
    } else if let bundled = Bundle.main.url(forResource: "rfc-index", withExtension: "xml") {
      // A snapshot shipped with the app makes first launch work offline.
      url = bundled
    } else {
      return nil
    }
    return (try RFCIndexParser.parse(contentsOf: url), updatedAt)
  }

  func storeIndex(_ data: Data) throws {
    try data.write(to: indexURL, options: .atomic)
  }

  // MARK: - Documents

  private func fileURL(_ id: DocumentID, format: FileFormat) -> URL {
    directory.appending(path: "\(id.fileStem).\(format.pathExtension)")
  }

  func isCached(_ id: DocumentID) -> Bool {
    FileManager.default.fileExists(atPath: fileURL(id, format: .xml).path)
      || FileManager.default.fileExists(atPath: fileURL(id, format: .text).path)
  }

  /// Numbers of every RFC with a cached body.
  func cachedNumbers() -> Set<Int> {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    return Set(
      names.compactMap { name in
        let stem = (name as NSString).deletingPathExtension
        guard stem.hasPrefix("rfc"), let id = DocumentID(parsing: stem) else { return nil }
        return id.number
      })
  }

  func remove(_ id: DocumentID) {
    parsed[id] = nil
    for format in [FileFormat.xml, .text] {
      try? FileManager.default.removeItem(at: fileURL(id, format: format))
    }
  }

  func document(_ id: DocumentID, formats: [FileFormat], client: RFCEditorClient) async throws
    -> RFCDocument
  {
    if let cached = parsed[id] { return cached }

    let xmlURL = fileURL(id, format: .xml)
    if let data = try? Data(contentsOf: xmlURL), let document = try? RFCXMLParser.parse(data) {
      parsed[id] = document
      return document
    }
    let textURL = fileURL(id, format: .text)
    if let data = try? Data(contentsOf: textURL) {
      let document = LegacyTextParser.parse(data)
      parsed[id] = document
      return document
    }

    // Not cached: fetch XML when the index says it exists, otherwise text.
    if formats.isEmpty || formats.contains(.xml) {
      if let data = try? await client.fetchDocumentData(id, format: .xml),
        let document = try? RFCXMLParser.parse(data)
      {
        try data.write(to: xmlURL, options: .atomic)
        parsed[id] = document
        return document
      }
    }
    let data = try await client.fetchDocumentData(id, format: .text)
    try data.write(to: textURL, options: .atomic)
    let document = LegacyTextParser.parse(data)
    parsed[id] = document
    return document
  }

  func originalText(_ id: DocumentID, client: RFCEditorClient) async throws -> String {
    let textURL = fileURL(id, format: .text)
    if let data = try? Data(contentsOf: textURL) {
      return LegacyTextParser.stripPagination(String(decoding: data, as: UTF8.self))
    }
    let data = try await client.fetchDocumentData(id, format: .text)
    try data.write(to: textURL, options: .atomic)
    return LegacyTextParser.stripPagination(String(decoding: data, as: UTF8.self))
  }
}
