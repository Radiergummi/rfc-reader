import Foundation
import RFCKit
import RFCReaderKit

/// On-disk cache of raw RFC files plus an in-memory cache of parsed documents.
///
/// Files are stored exactly as served by the RFC Editor, so the "original text"
/// view and re-parsing after a parser improvement both come for free.
actor DocumentStore {
  private let directory: URL
  private var parsed: [DocumentID: RFCDocument] = [:]

  /// Which bodies are on disk, scanned once on first use and kept current by
  /// every write and removal below, so asking does not enumerate the directory.
  /// Each question revalidates it first, which scans again only if the directory
  /// changed some other way, such as a file deleted in Finder.
  private lazy var cachedDocuments = DocumentCacheIndex(scanning: directory)

  /// Whether a body has been written since eviction last looked, so a cache that
  /// has not grown is not enumerated again.
  private var hasGrown = true

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
    directory.appending(path: DocumentCacheIndex.fileName(for: id, format: format))
  }

  func isCached(_ id: DocumentID) -> Bool {
    cachedDocuments.revalidate()
    return cachedDocuments.contains(id)
  }

  /// Numbers of every RFC with a cached body.
  func cachedNumbers() -> Set<Int> {
    cachedDocuments.revalidate()
    return cachedDocuments.rfcNumbers
  }

  /// A body that cannot be deleted is left where it is, and stays cached: the
  /// index records what the removal left on disk, not what it set out to do.
  func remove(_ id: DocumentID) {
    parsed[id] = nil
    let urls = DocumentCacheIndex.bodyFormats.map { fileURL(id, format: $0) }
    cachedDocuments.update(id) {
      for url in urls {
        try? FileManager.default.removeItem(at: url)
      }
    }
  }

  func document(_ id: DocumentID, formats: [FileFormat], client: RFCEditorClient) async throws
    -> RFCDocument
  {
    markOpened(id)
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
        try cachedDocuments.update(id) { try data.write(to: xmlURL, options: .atomic) }
        hasGrown = true
        parsed[id] = document
        return document
      }
    }
    let data = try await client.fetchDocumentData(id, format: .text)
    try cachedDocuments.update(id) { try data.write(to: textURL, options: .atomic) }
    hasGrown = true
    let document = LegacyTextParser.parse(data)
    parsed[id] = document
    return document
  }

  // MARK: - Eviction (#39)

  /// Records that `id` was opened, as its bodies' modification date: a body is
  /// never modified after it is written, so the date is free to mean "last opened",
  /// and it outlives the process. A file's date is not its directory's, so this
  /// does not send `DocumentCacheIndex` to scan again.
  private func markOpened(_ id: DocumentID) {
    for format in DocumentCacheIndex.bodyFormats {
      try? FileManager.default.setAttributes(
        [.modificationDate: Date.now], ofItemAtPath: fileURL(id, format: format).path)
    }
  }

  /// Removes the least recently opened bodies past `bound`, never a pinned one; see
  /// `CacheEviction`. Only after the cache has grown, so an ordinary open costs
  /// nothing here. Returns what it removed.
  @discardableResult
  func evict(pinned: Set<DocumentID>, bound: Int) -> [DocumentID] {
    guard hasGrown else { return [] }
    hasGrown = false
    let victims = CacheEviction.victims(
      of: CacheEviction.entries(in: directory), pinned: pinned, bound: bound)
    for id in victims {
      remove(id)
    }
    return victims
  }

  func originalText(_ id: DocumentID, client: RFCEditorClient) async throws -> String {
    let textURL = fileURL(id, format: .text)
    if let data = try? Data(contentsOf: textURL) {
      return LegacyTextParser.stripPagination(String(decoding: data, as: UTF8.self))
    }
    let data = try await client.fetchDocumentData(id, format: .text)
    try cachedDocuments.update(id) { try data.write(to: textURL, options: .atomic) }
    hasGrown = true
    return LegacyTextParser.stripPagination(String(decoding: data, as: UTF8.self))
  }
}
