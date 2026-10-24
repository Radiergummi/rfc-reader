import Foundation
import RFCKit

/// What `DraftStore` asks of the network: the two fetches of `RFCEditorClient` a
/// draft takes, so its tests can stand in for them.
public protocol DraftFetching: Sendable {
  /// What Datatracker says of the draft, whatever revision `id` names.
  @concurrent
  func fetchDraftInfo(_ id: DraftID) async throws -> (info: DraftInfo, data: Data)
  /// One revision, read from its text.
  @concurrent
  func fetchDraft(_ id: DraftID) async throws -> RFCEditorClient.FetchedDocument
  /// One revision's raw bytes in `format`: its text, for Original Text.
  func fetchDraftData(_ id: DraftID, format: FileFormat) async throws -> Data
}

extension RFCEditorClient: DraftFetching {}

/// The Internet-Drafts read (#728): each revision's text as the IETF's archive
/// serves it, and what Datatracker says of each draft.
///
/// A revision never changes once it is submitted, so its text is kept as an RFC's
/// body is, and read from the disk from then on, by the reader and Original Text
/// alike. Which revision is the newest does
/// change, and is asked of Datatracker again once what is kept is a day old
/// (`infoLifetime`), or whenever it cannot be had from the disk at all; a failed
/// ask falls back to what is kept, so a draft read once opens offline.
///
/// Apart from `DocumentStore`, whose tiers, eviction and packs are all about the
/// RFC Editor's series: a draft is never kept offline, never in a pack, and never in
/// the RFC index.
public actor DraftStore {
  /// How long what Datatracker said of a draft is taken as current (decision on #734).
  public static let infoLifetime: TimeInterval = 24 * 60 * 60

  private let directory: URL
  private let now: @Sendable () -> Date

  /// The revisions parsed last, so going back to one skips the parse.
  private var parsed = RecentValues<DraftID, RFCDocument>(capacity: 4)
  /// The fetches running, so a second open of the same revision joins the first.
  private var fetches: [DraftID: Task<RFCDocument, any Error>] = [:]
  /// The asks of Datatracker running, by draft name, which a second joins: a draft
  /// opened without a revision asks for its header and for its revision at once.
  private var infoFetches: [String: Task<DraftInfo, any Error>] = [:]

  /// The app's: a folder of Caches, since everything in it can be fetched again.
  public init() {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    self.init(directory: caches.appending(path: "RFCReader/Drafts", directoryHint: .isDirectory))
  }

  /// A store keeping its files in `directory`, which is created when it does not
  /// exist, and telling the time by `now`.
  public init(directory: URL, now: @escaping @Sendable () -> Date = Date.init) {
    self.directory = directory
    self.now = now
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  // MARK: - What Datatracker says

  /// What Datatracker says of the draft `id` names: as kept, while that is less than
  /// a day old and knows of the revision `id` names, and asked again otherwise, as
  /// for a link to a revision published since. Kept as it was when the ask fails,
  /// which is then the error only if nothing is kept.
  public func info(for id: DraftID, client: any DraftFetching) async throws -> DraftInfo {
    let kept = keptInfo(for: id)
    if let kept, now().timeIntervalSince(kept.fetchedAt) < Self.infoLifetime,
      !Self.names(id, newerThan: kept.info)
    {
      return kept.info
    }
    if let fetch = infoFetches[id.name] { return try await fetch.value }
    let url = infoURL(for: id)
    let fetch = Task {
      do {
        let fetched = try await client.fetchDraftInfo(id)
        try? fetched.data.write(to: url, options: .atomic)
        return fetched.info
      } catch {
        if let kept { return kept.info }
        throw error
      }
    }
    infoFetches[id.name] = fetch
    defer { infoFetches[id.name] = nil }
    return try await fetch.value
  }

  /// Whether `id` names a revision past the newest `info` knows of.
  private static func names(_ id: DraftID, newerThan info: DraftInfo) -> Bool {
    guard let revision = id.revision.flatMap({ Int($0) }),
      let newest = Int(info.newestRevision)
    else { return false }
    return revision > newest
  }

  /// What is kept of Datatracker's description, and when it was fetched: the file's
  /// modification date, which writing it again moves.
  private func keptInfo(for id: DraftID) -> (info: DraftInfo, fetchedAt: Date)? {
    let url = infoURL(for: id)
    guard let data = try? Data(contentsOf: url), let info = try? DraftInfo.decode(data),
      let fetchedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
        .contentModificationDate
    else { return nil }
    return (info, fetchedAt)
  }

  /// The revision `id` names: its own, or the newest Datatracker knows of.
  public func revision(of id: DraftID, client: any DraftFetching) async throws -> DraftID {
    if id.revision != nil { return id }
    let info = try await info(for: id, client: client)
    guard let newest = info.newest else { throw RFCEditorClient.ClientError.draftNotFound(id) }
    return newest
  }

  // MARK: - Revisions

  /// The revision `id` names, parsed: the newest when it names none. From the disk
  /// when it is kept there, and from the IETF's archive otherwise, which keeps it.
  public func document(_ id: DraftID, client: any DraftFetching) async throws -> RFCDocument {
    let revision = try await revision(of: id, client: client)
    if let document = parsed.value(for: revision) { return document }
    if let fetch = fetches[revision] { return try await fetch.value }
    let fetch = Task { [directory] in
      if let document = await Self.parseKept(revision, in: directory) { return document }
      let fetched = try await client.fetchDraft(revision)
      try? fetched.data.write(to: Self.fileURL(revision, in: directory), options: .atomic)
      return fetched.document
    }
    fetches[revision] = fetch
    defer { fetches[revision] = nil }
    let document = try await fetch.value
    parsed.store(document, for: revision)
    return document
  }

  /// The revision's plain text, without its page breaks, for Original Text: every
  /// revision has one at the archive, whatever it was submitted as. Kept once
  /// fetched, as the revision's file is.
  public func originalText(_ id: DraftID, client: any DraftFetching) async throws -> String {
    let revision = try await revision(of: id, client: client)
    // The reader's fetch of the same revision, running, is the one download: a draft
    // opened as its original text asks for both at once.
    if let fetch = fetches[revision] { _ = try? await fetch.value }
    let url = Self.fileURL(revision, in: directory)
    let data: Data
    if let kept = try? Data(contentsOf: url) {
      data = kept
    } else {
      data = try await client.fetchDraftData(revision, format: .text)
      try? data.write(to: url, options: .atomic)
    }
    return await Self.originalText(of: data)
  }

  /// The text without its page breaks, made off the actor, as a parse is.
  @concurrent
  private static func originalText(of data: Data) async -> String {
    LegacyTextParser.stripPagination(LegacyTextParser.text(decoding: data))
  }

  /// The kept text of `id`, parsed off the actor; nil when none is kept.
  @concurrent
  private static func parseKept(_ id: DraftID, in directory: URL) async -> RFCDocument? {
    guard let data = try? Data(contentsOf: fileURL(id, in: directory)) else { return nil }
    return RFCEditorClient.parseDraft(data, id: id)
  }

  // MARK: - Storage (#358)

  /// The revisions kept, and what they and Datatracker's descriptions take on the
  /// disk, which Settings' Storage tab counts with the reading cache.
  public func storageUsage() -> StorageUsage {
    let files = keptFiles()
    let bytes = files.reduce(0) { total, file in
      total + ((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }
    return StorageUsage(documents: files.filter { $0.pathExtension == "txt" }.count, bytes: bytes)
  }

  /// Removes every revision and description kept, as Settings' Clear Cache does:
  /// each can be fetched again.
  public func clear() {
    for file in keptFiles() {
      try? FileManager.default.removeItem(at: file)
    }
    parsed.removeAll { _ in true }
  }

  private func keptFiles() -> [URL] {
    (try? FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
  }

  private func infoURL(for id: DraftID) -> URL {
    directory.appending(path: "\(id.name).json")
  }

  private static func fileURL(_ id: DraftID, in directory: URL) -> URL {
    directory.appending(path: "\(id.description).txt")
  }
}
