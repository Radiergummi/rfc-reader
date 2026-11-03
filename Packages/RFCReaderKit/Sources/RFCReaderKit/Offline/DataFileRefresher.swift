import Foundation
import Observation
import RFCKit
import os

private let dataFileLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "me.mazetti.rfc-reader", category: "library")

/// The data files beside the index (#595): the revisions, the working groups, the
/// errata and the IANA registries, each read from the copy kept first, so it answers
/// offline, then fetched when it is due. A failure keeps what there is, leaves the next
/// refresh to try again, and is logged rather than shown (#125).
///
/// The revisions and the working groups are due once a day, by the copy kept, which a
/// new launch remembers, and by this run's last fetch (`DataFileCheck.fetch`, #758):
/// on any network when nothing is kept, and only on a network that is neither metered
/// nor in Low Data Mode when a copy is, since nobody is waiting for it.
@MainActor @Observable
public final class DataFileRefresher {
  /// `revisions.json`: adopted drafts that intend to obsolete or update an RFC. Nil
  /// until the copy kept or a fetch has arrived.
  public private(set) var revisions: RFCRevisions?
  /// `groups.json`: the groups the index names, for a working group's card (#363).
  /// Nil until the copy kept or a fetch has arrived.
  public private(set) var workingGroups: WorkingGroups?
  /// Every RFC's errata (#387), from the RFC Editor's feed: the copy kept first, then
  /// a check once a day. Nil until either has been read.
  public private(set) var errata: Errata?

  /// Called when `revisions` changed: read from the copy kept, or fetched and
  /// different.
  @ObservationIgnored public var onRevisionsChanged: () -> Void = {}

  @ObservationIgnored private let store: DocumentStore
  @ObservationIgnored private let client: RFCEditorClient
  /// For a fetch nobody is waiting for, which waits for a network that is neither
  /// metered nor in Low Data Mode instead of failing (#314).
  @ObservationIgnored private let clientOnCheapNetworks: RFCEditorClient
  @ObservationIgnored private let now: () -> Date

  /// When the copy of the revisions kept was written, read with it; nil until it
  /// has been read, or when none could be.
  @ObservationIgnored private var revisionsKeptAt: Date?
  /// When this run last fetched the revisions; nil until it has.
  @ObservationIgnored private var revisionsFetchedAt: Date?
  /// The refresh under way, which a second call joins rather than repeats. A
  /// launch's or an activation's gives way to the bookmark refresh's, which takes any
  /// network (#758).
  @ObservationIgnored private let revisionsRefresh = SharedRefresh(name: "Refresh revisions")

  /// As `revisionsKeptAt` and `revisionsFetchedAt` are for the revisions.
  @ObservationIgnored private var workingGroupsKeptAt: Date?
  @ObservationIgnored private var workingGroupsFetchedAt: Date?
  /// The refresh under way, which a second call leaves to finish alone.
  @ObservationIgnored private let workingGroupsRefresh = SharedRefresh(
    name: "Refresh working groups")

  /// The refresh under way, which a second call leaves to finish alone.
  @ObservationIgnored private let errataRefresh = SharedRefresh(name: "Refresh errata")
  /// When this run last had an answer from the RFC Editor for the feed, whatever came
  /// of it: a feed that fails to decode or to be kept records no check, and would
  /// otherwise be downloaded again at every activation. A request that fails is asked
  /// again at the next activation, as the other refreshes are.
  @ObservationIgnored private var errataAskedAt: Date?

  public init(
    store: DocumentStore, client: RFCEditorClient, clientOnCheapNetworks: RFCEditorClient,
    now: @escaping () -> Date = { .now }
  ) {
    self.store = store
    self.client = client
    self.clientOnCheapNetworks = clientOnCheapNetworks
    self.now = now
  }

  /// The revisions, the working groups and the errata, each as its own refresh does:
  /// what launch and every activation call.
  public func refreshAll() async {
    await withDiscardingTaskGroup { group in
      group.addTask { await self.refreshRevisions() }
      group.addTask { await self.refreshWorkingGroups() }
      group.addTask { await self.refreshErrata() }
    }
  }

  // MARK: - Revisions

  /// Reads the copy kept first, so the banner is right offline, then fetches it when
  /// it is due (`DataFileCheck.fetch`).
  ///
  /// A call while one is under way waits for that one, so that a background refresh
  /// that asks returns only once the file is in (#191). `onExpensiveNetworks` is the
  /// bookmark refresh's (#758): a due file is fetched on any network, at most once a
  /// day, since a background refresh on a phone network would otherwise post nothing
  /// about a revised bookmark. It replaces a refresh under way that waits for a cheap
  /// network, as a person's refresh of the index replaces the automatic check.
  public func refreshRevisions(onExpensiveNetworks: Bool = false) async {
    await revisionsRefresh.start(replaceable: !onExpensiveNetworks) {
      await self.loadRevisions(onExpensiveNetworks: onExpensiveNetworks)
    }.value
  }

  private func loadRevisions(onExpensiveNetworks: Bool) async {
    if revisions == nil, let kept = await store.cachedRevisions() {
      revisions = kept.value
      revisionsKeptAt = kept.keptAt
      onRevisionsChanged()
    }
    guard
      let fetch = DataFileCheck.fetch(
        keptAt: revisionsKeptAt, fetchedAt: revisionsFetchedAt, now: now())
    else { return }
    do {
      let fetched = try await client(for: fetch, onExpensiveNetworks: onExpensiveNetworks)
        .fetchRevisions()
      revisionsFetchedAt = now()
      if fetched.revisions != revisions {
        revisions = fetched.revisions
        onRevisionsChanged()
      }
      try await store.storeRevisions(fetched.data)
    } catch {
      // A refresh replaced by the bookmark refresh's is canceled on purpose.
      guard !Self.isCancellation(error) else { return }
      dataFileLog.error(
        "refreshing revisions failed: \(String(describing: error), privacy: .public)")
    }
  }

  // MARK: - Working groups

  /// As `refreshRevisions()` does for its file, and when it does: the copy kept
  /// first, so a card works offline, then a fetch when it is due.
  public func refreshWorkingGroups() async {
    await workingGroupsRefresh.runUnlessUnderWay { await self.loadWorkingGroups() }
  }

  private func loadWorkingGroups() async {
    if workingGroups == nil, let kept = await store.cachedWorkingGroups() {
      workingGroups = kept.value
      workingGroupsKeptAt = kept.keptAt
    }
    guard
      let fetch = DataFileCheck.fetch(
        keptAt: workingGroupsKeptAt, fetchedAt: workingGroupsFetchedAt, now: now())
    else { return }
    do {
      let fetched = try await client(for: fetch, onExpensiveNetworks: false)
        .fetchWorkingGroups()
      workingGroupsFetchedAt = now()
      if fetched.groups != workingGroups { workingGroups = fetched.groups }
      try await store.storeWorkingGroups(fetched.data)
    } catch {
      dataFileLog.error(
        "refreshing working groups failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// The client a due fetch goes through: any network when nothing answers meanwhile,
  /// or when the caller says so; otherwise only a cheap one.
  private func client(for fetch: DataFileCheck.Fetch, onExpensiveNetworks: Bool)
    -> RFCEditorClient
  {
    fetch == .anyNetwork || onExpensiveNetworks ? client : clientOnCheapNetworks
  }

  private static func isCancellation(_ error: any Error) -> Bool {
    error is CancellationError || (error as? URLError)?.code == .cancelled
  }

  // MARK: - Errata

  /// The copy of the errata feed kept, read the first time, then the RFC Editor asked
  /// for a newer one once a day, as the index is (#314): with the validators of the
  /// one kept, so an unchanged feed is a `304`, and on a network that is neither
  /// metered nor in Low Data Mode, since nobody is waiting for it.
  public func refreshErrata() async {
    await errataRefresh.runUnlessUnderWay { await self.loadErrata() }
  }

  private func loadErrata() async {
    if errata == nil, let data = await store.cachedErrata() {
      errata = try? await Self.decodeErrata(data)
    }
    // Without a feed in memory, a `304` would leave nothing to show.
    let kept = errata == nil ? nil : store.errataCheck()
    guard
      DataFileCheck.isErrataDue(
        keptCheckedAt: kept?.checkedAt, askedAt: errataAskedAt, now: now())
    else { return }
    do {
      let fetched = try await clientOnCheapNetworks.fetchErrataData(
        unlessMatching: kept?.validators(at: now()), onExpensiveNetworks: false)
      errataAskedAt = now()
      switch fetched {
      case .unchanged:
        if let kept { try await store.recordUnchangedErrata(kept) }
      case .changed(let data, let validators):
        // Shown before it is kept, so a failed write loses only the copy on disk.
        errata = try await Self.decodeErrata(data)
        try await store.storeErrata(data, validators: validators)
      }
    } catch {
      dataFileLog.error(
        "refreshing the errata failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// Off the main actor: the feed is every erratum ever reported.
  @concurrent
  private static func decodeErrata(_ data: Data) async throws -> Errata {
    try Errata.decode(data)
  }

  // MARK: - Registries

  /// The IANA registry values the Go to RFC palette looks up (#175). Not observed:
  /// the palette asks on each keystroke, and nothing on screen lists them.
  /// `registriesVersion` tells it when they change.
  @ObservationIgnored private var registryEntries: [RegistryEntry] = [] {
    didSet { registriesVersion += 1 }
  }

  /// Counts the changes to the registry values, observed, so that Go to RFC lists
  /// those that arrive while it is open: on iOS, its first open is what reads them
  /// (#579).
  public private(set) var registriesVersion = 0

  /// When the registries were last checked, nil until they first are.
  @ObservationIgnored private var registriesCheckedAt: Date?

  /// Open once the registries are readable, for `loadedRegistryEntries()`: the
  /// cached ones read, and the ones never fetched fetched, or failed to be. Not the
  /// refreshes after them, which may wait for a cheap network.
  @ObservationIgnored private let registriesReadable = Latch()

  /// Checks the registries again if the last check is older than
  /// `RegistryRefresh.maximumAge`: the palette asks as it opens, since the app may
  /// stay open for weeks after the check at launch. Reads them first when nothing
  /// has: iOS does not at launch, and its Go to RFC sheet lists registry values too
  /// (#769, #579).
  public func refreshRegistriesIfDue() {
    guard let checked = registriesCheckedAt else {
      loadRegistriesUnlessChecked()
      return
    }
    guard RegistryRefresh.isDue(checkedAt: checked, now: now()) else { return }
    Task(name: "Refresh registries") { await refreshRegistries() }
  }

  /// Reads the registries unless something has already: what the Mac does at launch,
  /// where ⌘L may come first thing. Immediate, as `loadedRegistryEntries()`'s is, so
  /// the check is marked before either can look (#192).
  public func loadRegistriesUnlessChecked() {
    guard registriesCheckedAt == nil else { return }
    Task.immediate(name: "Load registries") { await refreshRegistries() }
  }

  /// Reads the cached registries, then fetches those that are due: a first fetch on
  /// any network, a refresh only on a cheap one (`RegistryRefresh`). A registry that
  /// cannot be fetched keeps its cached entries, and is logged rather than shown
  /// (#125): the palette still finds RFCs without it.
  private func refreshRegistries() async {
    // Set before the first suspension, so a palette opened meanwhile does not start
    // a second check.
    registriesCheckedAt = now()
    var cached = await store.cachedRegistries(maximumAge: RegistryRefresh.maximumAge)
    registryEntries = IANARegistry.allCases.flatMap { cached.entries[$0] ?? [] }
    let fetches = RegistryRefresh.fetches(stale: cached.stale, cached: Set(cached.entries.keys))
    for fetch in fetches {
      // The first fetches come first (`RegistryRefresh`): what is left are refreshes.
      if !fetch.onExpensiveNetworks { registriesReadable.open() }
      let registry = fetch.registry
      let fetched: (entries: [RegistryEntry], data: Data)
      do {
        fetched = try await (fetch.onExpensiveNetworks ? client : clientOnCheapNetworks)
          .fetchRegistry(registry, onExpensiveNetworks: fetch.onExpensiveNetworks)
      } catch {
        dataFileLog.error(
          "fetching the \(registry.file, privacy: .public) registry failed: \(String(describing: error), privacy: .public)"
        )
        continue
      }
      // Listed as soon as it is read, not after the slowest of the others, and
      // whether or not it can be kept for the next launch.
      cached.entries[registry] = fetched.entries
      registryEntries = IANARegistry.allCases.flatMap { cached.entries[$0] ?? [] }
      do {
        try await store.storeRegistry(fetched.data, for: registry)
      } catch {
        dataFileLog.error(
          "caching the \(registry.file, privacy: .public) registry failed: \(String(describing: error), privacy: .public)"
        )
      }
    }
    registriesReadable.open()
  }

  /// The registry values `query` names exactly: `425`, `tls alert 70`,
  /// `application/dns-message`, read as a pasted reference is: `425.` and `(425)`
  /// name what `425` does.
  public func registryMatches(for query: String) -> [RegistryEntry] {
    DocumentReference.registryMatches(for: query, in: registryEntries)
  }

  /// The registry entries an App Intent asks for (#192), once they are readable.
  /// Only the Mac reads them at launch, and an intent may be the first to ask on
  /// either platform, so this starts the read when nothing has, in a task of its own.
  public func loadedRegistryEntries() async -> [RegistryEntry] {
    // Immediate, so the check is marked before this suspends and a second query
    // asking meanwhile does not read them again.
    loadRegistriesUnlessChecked()
    await registriesReadable.wait()
    return registryEntries
  }
}
