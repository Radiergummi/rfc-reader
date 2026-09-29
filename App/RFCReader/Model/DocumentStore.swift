import Foundation
import RFCKit
import RFCReaderKit
import os

nonisolated private let storeLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "me.mazetti.rfc-reader", category: "store")

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

  /// The fetches running, so a second open joins the first, a removal made during
  /// one keeps its result off the disk, and one nobody waits for any more is
  /// cancelled (#116). Original Text fetches the `.txt` on its own, so it has its
  /// own.
  private let downloads = InFlightDownloads<RFCEditorClient.FetchedDocument>()
  private let originalTexts = InFlightDownloads<Data>()

  /// Whether a body has been written since eviction last looked, so a cache that
  /// has not grown is not enumerated again.
  private var hasGrown = true

  /// The installed data packs (#36), in a folder of the cache's directory but not
  /// part of the cache: a pack is installed and replaced whole, never evicted a
  /// document at a time. The cache's index and eviction read only the bodies the
  /// store names itself, at the directory's top level, so a folder is never one.
  private var packsDirectory: URL {
    directory.appending(path: "Packs", directoryHint: .isDirectory)
  }

  /// The converted legacy RFCs, the one pack the app reads so far. Nil until one
  /// is installed.
  private lazy var legacyPack: InstalledPack? = Self.installedPack(
    in: packsDirectory.appending(path: Self.legacyPackName, directoryHint: .isDirectory))
  private static let legacyPackName = "legacy-xml"
  /// One install at a time: two would unpack into one destination and race to
  /// swap it in.
  private var isInstallingPack = false

  struct AlreadyInstalling: Error, CustomStringConvertible {
    var description: String { "A data pack is already being installed." }
  }

  struct DownloadFailed: Error, CustomStringConvertible {
    let url: URL
    let status: Int
    var description: String { "\(url.absoluteString) answered HTTP \(status)" }
  }

  init() {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
      0]
    directory = support.appending(path: "RFCReader", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  // MARK: - Index

  private nonisolated var indexURL: URL { directory.appending(path: "rfc-index.xml") }

  /// Where the cached index is, and when it was written: the RFC Editor's copy in the
  /// cache, or else the snapshot bundled with the app. Nil when there is neither.
  ///
  /// Only a lookup, and nonisolated: the caller parses it, off this actor (#367).
  /// Parsed here, the index held the store for as long as the parse took, so a
  /// document opened during launch — an `rfc://` link — waited behind it.
  nonisolated func cachedIndexLocation() -> (url: URL, updatedAt: Date)? {
    if FileManager.default.fileExists(atPath: indexURL.path) {
      let updatedAt =
        (try? indexURL.resourceValues(forKeys: [.contentModificationDateKey])
          .contentModificationDate) ?? .distantPast
      return (indexURL, updatedAt)
    } else if let bundled = Bundle.main.url(forResource: "rfc-index", withExtension: "xml") {
      // A snapshot shipped with the app makes first launch work offline.
      return (bundled, .distantPast)
    } else {
      return nil
    }
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

  /// How much disk the cached body takes, or nil when there is none.
  func downloadedSize(_ id: DocumentID) -> Int? {
    let sizes = DocumentCacheIndex.bodyFormats.compactMap { format in
      (try? fileURL(id, format: format).resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }
    return sizes.isEmpty ? nil : sizes.reduce(0, +)
  }

  /// Numbers of every RFC with a cached body.
  func cachedNumbers() -> Set<Int> {
    cachedDocuments.revalidate()
    return cachedDocuments.rfcNumbers
  }

  /// A body that cannot be deleted is left where it is, and stays cached: the
  /// index records what the removal left on disk, not what it set out to do.
  func remove(_ id: DocumentID) {
    downloads.removed(id)
    originalTexts.removed(id)
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
    // Before a cached `.txt`: the pack is the single XML path it exists for, and a
    // `.txt` cached before it arrived still serves Original Text.
    if let packURL = legacyPack?.file(for: id) {
      do {
        let document = try RFCXMLParser.parse(Data(contentsOf: packURL))
        parsed[id] = document
        return document
      } catch {
        storeLog.error(
          "\(id.displayName, privacy: .public): not read from the data pack: \(String(describing: error), privacy: .public)"
        )
      }
    }
    let textURL = fileURL(id, format: .text)
    if let data = try? Data(contentsOf: textURL) {
      let document = LegacyTextParser.parse(data)
      parsed[id] = document
      return document
    }

    let (fetched, isKept) = try await downloads.value(for: id) {
      Task { try await Self.fetch(id, formats: formats, client: client) }
    }
    // A removal while this was in flight, or another reader of the same fetch has
    // kept it: the document is shown, and not written here (#116).
    guard isKept else { return fetched.document }
    let url = fileURL(id, format: fetched.format)
    try cachedDocuments.update(id) { try fetched.data.write(to: url, options: .atomic) }
    hasGrown = true
    // A pack installed while this was in flight serves the document from now on.
    if legacyPack?.file(for: id) == nil {
      parsed[id] = fetched.document
    }
    return fetched.document
  }

  /// Not cached: the XML when the index says it exists, otherwise the text, and the
  /// text only when there is no XML (#125). Off the actor, parse included, so the
  /// store answers other calls meanwhile.
  private static func fetch(_ id: DocumentID, formats: [FileFormat], client: RFCEditorClient)
    async throws -> RFCEditorClient.FetchedDocument
  {
    let fetched = try await client.fetchPreferredDocument(
      id, availableFormats: formats.isEmpty ? nil : formats)
    if let failure = fetched.xmlParseFailure {
      storeLog.error(
        "\(id.displayName, privacy: .public): XML did not parse, shown from the text: \(String(describing: failure), privacy: .public)"
      )
    }
    return fetched
  }

  // MARK: - Data packs (#36)

  /// The pack in `directory`, or nil when none is installed there or its manifest
  /// does not read. That is logged, because the store would otherwise fall back to
  /// the network with no sign of why.
  private static func installedPack(in directory: URL) -> InstalledPack? {
    guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else {
      return nil
    }
    do {
      return try InstalledPack(contentsOf: directory)
    } catch {
      storeLog.error(
        "the installed data pack is unreadable: \(String(describing: error), privacy: .public)")
      return nil
    }
  }

  /// Installs the legacy XML pack from an `.aar`, an unpacked folder, or a URL to
  /// download one from, replacing the installed one only once the new one has
  /// verified. Documents already parsed are parsed again on their next open, so
  /// they come from the pack.
  func installLegacyPack(from source: URL) async throws -> InstalledPack {
    // Checked and set without a suspension between them, so a second install
    // arriving while the first is off the actor is refused rather than raced.
    guard !isInstallingPack else { throw AlreadyInstalling() }
    isInstallingPack = true
    defer { isInstallingPack = false }
    let pack = try await Self.install(source, as: Self.legacyPackName, in: packsDirectory)
    legacyPack = pack
    // Parsed again on their next open, from the pack; nothing else it could serve.
    for id in parsed.keys where pack.file(for: id) != nil {
      parsed[id] = nil
    }
    return pack
  }

  /// Off the actor: a whole pack is unpacked and every file hashed.
  @concurrent
  private static func install(_ source: URL, as name: String, in packs: URL) async throws
    -> InstalledPack
  {
    guard !source.isFileURL else {
      return try PackInstaller.install(source, as: name, in: packs)
    }
    let (downloaded, response) = try await URLSession.shared.download(from: source)
    defer { try? FileManager.default.removeItem(at: downloaded) }
    // An error page is not an archive, and would be reported as one that failed
    // to unpack.
    if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
      throw DownloadFailed(url: source, status: status)
    }
    return try PackInstaller.install(downloaded, as: name, in: packs)
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

  /// Whether a body has been written since eviction last ran: asked before the
  /// caller builds the pinned set, which is not free.
  var hasGrownSinceEviction: Bool { hasGrown }

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
    let (data, isKept) = try await originalTexts.value(for: id) {
      Task { try await client.fetchDocumentData(id, format: .text) }
    }
    if isKept {
      try cachedDocuments.update(id) { try data.write(to: textURL, options: .atomic) }
      hasGrown = true
    }
    return LegacyTextParser.stripPagination(String(decoding: data, as: UTF8.self))
  }
}
