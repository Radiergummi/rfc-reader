import RFCKit
import RFCReaderKit
import SwiftUI
import os

/// The reader's load and build decisions, at debug level: what a device's
/// Console shows when a document fails to load or never finishes (#252, #253).
let readerLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "me.mazetti.rfc-reader", category: "reader")

/// Everything a build depends on. One trigger, so the document is built in one
/// place whatever changed — a new RFC, a reading setting, or a window resize.
struct BuildInputs: Equatable {
  /// Distinguishes "not fetched yet" from "fetched", so finishing a fetch
  /// triggers the build. A session only ever fetches into a state with no
  /// document, so every load arrives as a false → true transition.
  let hasDocument: Bool
  let fontSize: Double
  let underlineLinks: Bool
  let textSize: DynamicTypeSize
  let legibilityWeight: LegibilityWeight?
  let column: CGFloat?

  var style: ReadingStyle? {
    column.map {
      ReadingStyle(
        bodySize: fontSize, measure: $0, underlinesLinks: underlineLinks, textSize: textSize)
    }
  }
}

/// One document in one reader (#135): its fetch, its build, and the state the reader
/// renders from.
///
/// Owned by the view rather than by `.task`, which ties the work to appearance: in a
/// collapsed split view, a reader pushed over one that was popped is told it
/// disappeared the moment it appears, and is never told it appeared again. `.task`
/// cancelled the fetch on that notice and nothing started it again, so the reader
/// spun forever while on screen (#252 was the same cancellation, shown as an error).
///
/// A reference held in the view's state, so it goes when that state does, which is
/// when the view is replaced by the next document's (`.id(selection)`): the old
/// reader's fetch and 650 ms build are cancelled then, rather than running on for a
/// document nobody will see. Disappearing is not going (#252).
@Observable
final class DocumentSession {
  let id: DocumentID

  private(set) var state = LoadState()
  /// Anchor to section number, made once with the document. See
  /// `DocumentView`'s `onVisibleAnchorChange` for why it is not asked of the
  /// document each time.
  private(set) var sectionNumbers: [String: String] = [:]

  @ObservationIgnored private var load: Task<Void, Never>?
  @ObservationIgnored private var build: Task<Void, Never>?
  /// The inputs the build under way is for.
  @ObservationIgnored private var buildingFor: BuildInputs?
  /// What the document on screen was built from, so a change that comes back to
  /// where it started does not build it again.
  @ObservationIgnored private var builtInputs: BuildInputs?

  init(id: DocumentID) {
    self.id = id
  }

  deinit {
    load?.cancel()
    build?.cancel()
  }

  var hasStartedLoading: Bool { load != nil }

  /// Fetches, and hands the document to `loaded` once it is the state's. Building is
  /// `requestBuild`'s job, which the document arriving triggers.
  ///
  /// Once per session, plus Try Again after a failure: the view is made per document
  /// (`.id(selection)`), and appearing again keeps what it loaded.
  func startLoad(from library: LibraryModel, loaded: @escaping (RFCDocument) -> Void) {
    load?.cancel()
    state.begin()
    load = Task(name: "Load document") {
      trace("loading")
      do {
        let document = try await library.document(for: id)
        sectionNumbers = Dictionary(
          document.allSections.compactMap { section in
            section.number.map { (section.anchor, $0) }
          },
          uniquingKeysWith: { first, _ in first }
        )
        state.finish(document)
        loaded(document)
        trace("loaded")
      } catch {
        trace("failed: \(error)")
        state.fail(error)
      }
    }
  }

  /// Builds for `inputs`, unless the document on screen or the build under way is
  /// already for them, and hands the build to `built` once it is the state's.
  func requestBuild(for inputs: BuildInputs, built: @escaping (BuiltDocument) -> Void) {
    // Appearing again asks with nothing changed. A build already made, or under
    // way, for these inputs is left to stand rather than cancelled and paid for
    // twice.
    guard inputs != builtInputs, inputs != buildingFor else {
      trace("build skipped, inputs unchanged")
      return
    }
    build?.cancel()
    buildingFor = inputs
    build = Task(name: "Build document") {
      guard let document = state.document, let style = inputs.style else { return }
      trace("building")
      let delay = state.buildDelay
      if delay > .zero {
        try? await Task.sleep(for: delay)
      }
      // Before the build, which cannot be interrupted once it starts.
      guard !Task.isCancelled else { return }
      // Off the main actor: this is string assembly and text measurement, and
      // blocking the main thread for it is what made the font-size slider stutter.
      let rebuilt = await DocumentView.build(document, style: style)
      guard !Task.isCancelled else {
        trace("build cancelled, discarded")
        return
      }
      state.install(rebuilt)
      builtInputs = inputs
      trace("built")
      built(rebuilt)
    }
  }

  private func trace(_ event: String) {
    readerLog.debug("\(self.id.displayName, privacy: .public): \(event, privacy: .public)")
  }
}
