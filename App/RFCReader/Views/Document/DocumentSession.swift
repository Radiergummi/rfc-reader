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
/// canceled the fetch on that notice and nothing started it again, so the reader
/// spun forever while on screen (#252 was the same cancellation, shown as an error).
///
/// A reference held in the view's state, so it goes when that state does, which is
/// when the view is replaced by the next document's (`.id(selection)`): the old
/// reader's fetch and 650 ms build are canceled then, rather than running on for a
/// document nobody will see. Disappearing is not going (#252).
@Observable
final class DocumentSession {
  let id: DocumentID

  private(set) var state = LoadState()
  /// Anchor to the section's place (`Section.place`), made once with the document. See
  /// `DocumentView`'s `onVisibleAnchorChange` for why it is not asked of the
  /// document each time.
  private(set) var sectionPlaces: [String: String] = [:]

  /// The original text (`reader.showOriginal`), fetched the first time it is shown,
  /// and why it could not be.
  private(set) var originalText: String?
  private(set) var originalTextFailure: LoadFailure?

  @ObservationIgnored private var load: Task<Void, Never>?
  /// The original text's fetch, held for the reason `load` is: a `.task` on the
  /// original text view was canceled by the spurious disappearance, and its failure
  /// left the view spinning with nothing to try again.
  @ObservationIgnored private var originalTextLoad: Task<Void, Never>?
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
    originalTextLoad?.cancel()
  }

  var hasStartedLoading: Bool { load != nil }
  var hasStartedOriginalTextLoad: Bool { originalTextLoad != nil }

  /// Fetches the original text: once per session, the first time it is shown, plus
  /// Try Again after a failure. Holds the session weakly, for the reason `startLoad`
  /// gives.
  func startOriginalTextLoad(from library: LibraryModel) {
    originalTextLoad?.cancel()
    originalTextFailure = nil
    originalTextLoad = Task(name: "Load original text") { [weak self, id] in
      do {
        let text = try await library.originalText(for: id)
        guard let self, !Task.isCancelled else { return }
        originalText = text
      } catch {
        // Canceled only when the session goes, or when Try Again replaces this
        // fetch, and neither wants an error on screen.
        guard let self, !Task.isCancelled else { return }
        trace("original text failed: \(error)")
        originalTextFailure = LoadFailure(error: error)
      }
    }
  }

  /// Fetches, and hands the document to `loaded` once it is the state's, or says it
  /// `failed`. Building is `requestBuild`'s job, which the document arriving
  /// triggers.
  ///
  /// Once per session, plus Try Again after a failure: the view is made per document
  /// (`.id(selection)`), and appearing again keeps what it loaded.
  ///
  /// The task holds the session weakly, and neither closure may capture the view: a
  /// view's state holds this session, so either would keep it alive for as long as
  /// the fetch runs, and `deinit` could not cancel a fetch nobody waits for any more.
  /// A fetch that outlives its session is dropped, rather than writing an old
  /// document's details over the window's reader state.
  func startLoad(
    from library: LibraryModel, loaded: @escaping (RFCDocument) -> Void,
    failed: @escaping () -> Void
  ) {
    load?.cancel()
    state.begin()
    trace("loading")
    load = Task(name: "Load document") { [weak self, id] in
      do {
        let document = try await library.document(for: id)
        guard let self, !Task.isCancelled, state.isLoading else { return }
        sectionPlaces = Dictionary(
          document.allSections.compactMap { section in
            section.place.map { (section.anchor, $0) }
          },
          uniquingKeysWith: { first, _ in first }
        )
        state.finish(document)
        loaded(document)
        trace("loaded")
      } catch {
        guard let self, !Task.isCancelled else { return }
        trace("failed: \(error)")
        state.fail(error)
        failed()
      }
    }
  }

  /// Builds for `inputs`, as `BuildRequest` decides, and hands the build and its
  /// document to `built` once it is the state's. `built` must not capture the view,
  /// for the reason `startLoad` gives.
  func requestBuild(
    for inputs: BuildInputs, built: @escaping (BuiltDocument, RFCDocument) -> Void
  ) {
    switch BuildRequest.decide(inputs, built: builtInputs, building: buildingFor) {
    case .keep:
      trace("build skipped, inputs unchanged")
      return
    case .cancel:
      trace("build canceled, back to the inputs on screen")
      build?.cancel()
      buildingFor = nil
      return
    case .start:
      break
    }
    build?.cancel()
    // Recorded only once a build starts: a request with nothing to build yet would
    // otherwise name a build that does not exist, and the same inputs coming back
    // would be kept waiting for it.
    guard let document = state.document, let style = inputs.style else {
      buildingFor = nil
      return
    }
    buildingFor = inputs
    let delay = state.buildDelay(changingColumn: inputs.column != builtInputs?.column)
    trace("building")
    build = Task(name: "Build document") { [weak self] in
      if delay > .zero {
        try? await Task.sleep(for: delay)
      }
      // Before the build, which cannot be interrupted once it starts.
      guard !Task.isCancelled else { return }
      // Off the main actor: this is string assembly and text measurement, and
      // blocking the main thread for it is what made the font-size slider stutter.
      let rebuilt = await DocumentView.build(document, style: style)
      guard let self, !Task.isCancelled else { return }
      state.install(rebuilt)
      builtInputs = inputs
      buildingFor = nil
      trace("built")
      built(rebuilt, document)
    }
  }

  private func trace(_ event: String) {
    readerLog.debug("\(self.id.displayName, privacy: .public): \(event, privacy: .public)")
  }
}
