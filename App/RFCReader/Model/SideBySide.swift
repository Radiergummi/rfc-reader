import Foundation
import Observation
import RFCKit
import RFCReaderKit
import os

/// A document read beside the one it obsoletes, or the one obsoleting it, the two
/// scrolling together section by section (#187).
///
/// The document opened beside is a second reader with its own `NavigationModel` and
/// `ReaderState`, so it loads, builds and scrolls as any reader does, and what it
/// reports reaches neither the window's toolbar nor its panel, which stay the first
/// reader's. The two meet only in `coupling`.
///
/// The counterparts are aligned on the device, from the two documents, with
/// `SectionAlignment`: nothing in the app reads the corpus's `successions` table yet,
/// and both documents are loaded anyway. The scrolling takes rows, so reading the
/// table can replace this later.
@Observable
final class SideBySide {
  let pair: SideBySidePair
  /// The reader beside: its own place in the documents, and its own reader state.
  let navigation: NavigationModel
  let reader = ReaderState()
  @ObservationIgnored let coupling: ScrollCoupling
  private(set) var alignment = SideBySidePair.Alignment.aligning
  /// The document whose reader holds still, while the other is in a section with no
  /// counterpart in it.
  private(set) var holdsStill: DocumentID?

  @ObservationIgnored private var aligning: Task<Void, Never>?

  init(_ pair: SideBySidePair, library: LibraryModel) {
    self.pair = pair
    navigation = NavigationModel(library: library, listsDocuments: false)
    navigation.open(pair.other, in: library.index)
    coupling = ScrollCoupling(leader: pair.reading, follower: pair.other)
    reader.coupling = coupling
    coupling.onUnaligned = { [weak self] leader, section in
      guard let self else { return }
      holdsStill = section == nil ? nil : coupling.other(than: leader)
    }
  }

  isolated deinit {
    aligning?.cancel()
  }

  /// Aligns the two, among the old document's other successors and the new one's
  /// other predecessors that are already on the device. Those are aligned alongside
  /// for what they take away: a section that moved to one of them is not paired with
  /// its nearest, wrong, counterpart here (`SideBySidePair.alignedAmong`).
  func align(library: LibraryModel) {
    aligning?.cancel()
    alignment = .aligning
    aligning = Task(name: "Align \(pair.old.displayName) with \(pair.new.displayName)") {
      [weak self, pair] in
      let oldSuccessors = library.metadata(pair.old)?.obsoletedBy ?? []
      let newPredecessors = library.metadata(pair.new)?.obsoletes ?? []
      var available: Set<DocumentID> = []
      for id in oldSuccessors + newPredecessors where await library.isDownloaded(id) {
        available.insert(id)
      }
      let ids = pair.alignedAmong(
        oldSuccessors: oldSuccessors, newPredecessors: newPredecessors, available: available)
      var documents: [RFCDocument] = []
      do {
        for id in [pair.old, pair.new] {
          documents.append(try await library.document(for: id))
        }
      } catch {
        sideBySideLog.error(
          "aligning failed: \(String(describing: error), privacy: .public)")
        if !Task.isCancelled { self?.alignment = .failed }
        return
      }
      // The others only sharpen the pair's counterparts: one that fails to load is
      // left out, and the two are aligned without it.
      for id in ids.dropFirst(2) {
        if let document = try? await library.document(for: id) { documents.append(document) }
      }
      let rows = await Self.pairs(among: documents)
      guard let self, !Task.isCancelled else { return }
      coupling.scrolling = AlignedScrolling(rows: rows, between: pair.old, and: pair.new)
      alignment = .aligned
    }
  }

  /// Off the main actor: every section of each document is scored against every
  /// section of the other.
  @concurrent
  private static func pairs(among documents: [RFCDocument]) async -> [AlignedSection] {
    SectionAlignment.pairs(among: documents)
  }
}

nonisolated private let sideBySideLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "me.mazetti.rfc-reader", category: "side-by-side")
