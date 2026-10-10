import RFCKit
import RFCReaderKit
import SwiftUI
import os

/// The reader's load and build decisions: what a device's Console shows when a
/// document fails to load or never finishes (#252, #253). Progress is logged at
/// debug level, which is shown only while streaming; a failure at error level,
/// which the unified log keeps (#759).
let readerLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "me.mazetti.rfc-reader", category: "reader")

extension Logger {
  /// Something done with a document that failed, at error level, which the unified
  /// log keeps: "RFC 9110: `event`: `cause`".
  func failure(of document: DocumentID, _ event: String, _ cause: any Error) {
    error(
      "\(document.displayName, privacy: .public): \(event, privacy: .public): \(String(describing: cause), privacy: .public)"
    )
  }
}

/// Everything a build depends on. One trigger, so the document is built in one
/// place whatever changed — a new RFC, a reading setting, or a window resize.
struct BuildInputs: Equatable {
  /// Distinguishes "not fetched yet" from "fetched", so finishing a fetch
  /// triggers the build. A session only ever fetches into a state with no
  /// document, so every load arrives as a false → true transition.
  let hasDocument: Bool
  let legibilityWeight: LegibilityWeight?
  let column: CGFloat?
  /// The build-time half of the reader's settings, for `column`, and nil until
  /// there is one. Only this half: a draw-time setting (`ReaderSettings.palette`)
  /// must not be a reason to build again.
  let style: ReadingStyle?
  /// How the blocks with a rendering are shown: the preference, and the reader's
  /// choices from a block's menu. Not part of `ReadingStyle`, which keys the
  /// preview cache: a force-click preview shows every block rendered.
  let choices: PresentationChoices

  /// - Parameter hang: how far the headings' numbers hang in the gutter, in a style,
  ///   or zero where they don't (#433). Asked of the style rather than given, since
  ///   how far they hang depends on its sizes; and the hang rather than the gutter's
  ///   width, so a resize rebuilds only where the numbers come or go.
  init(
    hasDocument: Bool, settings: ReaderSettings, textSize: DynamicTypeSize,
    legibilityWeight: LegibilityWeight?, column: CGFloat?, choices: PresentationChoices,
    hang: (ReadingStyle) -> CGFloat = { _ in 0 }
  ) {
    self.hasDocument = hasDocument
    self.legibilityWeight = legibilityWeight
    self.column = column
    style = column.map { column in
      var style = settings.style(column: column, textSize: textSize)
      style.sectionNumberHang = hang(style)
      return style
    }
    self.choices = choices
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
  /// The reader's place in the tab's stack of readers on iOS (#263), nil on the Mac:
  /// what says whether the reader is the one on screen (`NavigationModel.shows`),
  /// and so whether what it loads and builds goes into the window's reader state.
  let depth: Int?

  private(set) var state = LoadState()
  /// Anchor to the section's place (`Section.place`), made once with the document. See
  /// `DocumentView`'s `onVisibleAnchorChange` for why it is not asked of the
  /// document each time.
  private(set) var sectionPlaces: [String: String] = [:]

  /// How far the document's heading numbers hang in a style (#433), measured once
  /// per set of fonts: asked on every update pass, for whether they fit the gutter.
  @ObservationIgnored private var measuredHang: (fonts: HangFonts, hang: CGFloat)?

  /// What a measured hang depends on.
  private struct HangFonts: Equatable {
    let style: ReadingStyle
    let legibilityWeight: LegibilityWeight?
  }

  /// `legibilityWeight` is Bold Text, which UIKit applies to the fonts as it makes
  /// them, and so widens the numbers without changing the style.
  func sectionNumberHang(in style: ReadingStyle, legibilityWeight: LegibilityWeight?) -> CGFloat {
    guard let document = state.document else { return 0 }
    // Kept by the fonts alone: the column moves on every step of a resize, and the
    // numbers' widths do not move with it.
    var style = style
    style.measure = ReaderLayout.idealMeasure
    style.sectionNumberHang = 0
    let fonts = HangFonts(style: style, legibilityWeight: legibilityWeight)
    if let measuredHang, measuredHang.fonts == fonts { return measuredHang.hang }
    let hang = SectionNumberHang.width(of: document, style: style)
    measuredHang = (fonts, hang)
    return hang
  }

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

  init(id: DocumentID, depth: Int?) {
    self.id = id
    self.depth = depth
  }

  deinit {
    progressDelay?.cancel()
    load?.cancel()
    build?.cancel()
    originalTextLoad?.cancel()
  }

  /// The index says the RFC is a scan, with no text to fetch (#207).
  @ObservationIgnored private var skipsLoad = false

  var hasStartedLoading: Bool { load != nil || skipsLoad }
  /// Whether the document is on its way: loading, and not an RFC whose original is
  /// shown instead.
  var awaitsDocument: Bool { state.isLoading && !skipsLoad }

  var hasStartedOriginalTextLoad: Bool { originalTextLoad != nil }

  /// Whether the reader waits before it says it is loading (`LoadState.progressDelay`,
  /// #263): on iOS, where a reader is pushed, and not on the Mac.
  #if os(macOS)
    private static let delaysProgress = false
  #else
    private static let delaysProgress = true
  #endif
  /// Whether the reader has had nothing to show for long enough to say it is
  /// loading.
  private(set) var isProgressDue = !DocumentSession.delaysProgress
  @ObservationIgnored private var progressDelay: Task<Void, Never>?

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
        readerLog.failure(of: id, "loading the original text failed", error)
        originalTextFailure = LoadFailure(error: error)
      }
    }
  }

  /// Starts no fetch, for a scan or a pointer the pack lists, and counts as started:
  /// appearing again, which a collapsed split view does spuriously, does not try the
  /// load after all.
  func skipLoad() {
    load?.cancel()
    load = nil
    skipsLoad = true
    trace("load skipped, its original is shown")
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
    delayProgress()
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
        measuredHang = nil
        state.finish(document)
        loaded(document)
        trace("loaded")
      } catch {
        guard let self, !Task.isCancelled else { return }
        readerLog.failure(of: id, "loading failed", error)
        state.fail(error)
        failed()
      }
    }
  }

  /// Starts the wait before the reader says it is loading. Held here rather than in
  /// a `.task`, for the reason `startLoad` gives: a task canceled by a spurious
  /// disappearance would leave a slow load with nothing on screen at all.
  private func delayProgress() {
    progressDelay?.cancel()
    isProgressDue = !Self.delaysProgress
    guard Self.delaysProgress else { return }
    progressDelay = Task(name: "Delay progress") { [weak self] in
      try? await Task.sleep(for: LoadState.progressDelay)
      guard let self, !Task.isCancelled else { return }
      isProgressDue = true
    }
  }

  /// Builds for `inputs`, as `BuildRequest` decides, and lists the sections the
  /// build holds into `reader` once it is the state's: unless the reader is not the
  /// one on screen, which a replaced reader's rebuild through its fade is not
  /// (`ReaderHost`), nor one the stack keeps below its top on iOS (#263).
  /// `resizeIsLive` is whether a new column comes from a resize still under way; see
  /// `ReaderResize`.
  func requestBuild(
    for inputs: BuildInputs, resizeIsLive: Bool, into reader: ReaderState.Writer
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
    let delay = state.buildDelay(
      for: ColumnChange(from: builtInputs?.column, to: inputs.column, isLive: resizeIsLive))
    trace("building")
    build = Task(name: "Build document") { [weak self, reader] in
      if delay > .zero {
        try? await Task.sleep(for: delay)
      }
      // Before the build, which cannot be interrupted once it starts.
      guard !Task.isCancelled else { return }
      // Off the main actor: this is string assembly and text measurement, and
      // blocking the main thread for it is what made the font-size slider stutter.
      let rebuilt = await Self.built(document, style: style, choices: inputs.choices)
      guard let self, !Task.isCancelled else { return }
      state.install(rebuilt)
      builtInputs = inputs
      buildingFor = nil
      trace("built")
      reader { $0.sections = rebuilt.reachableSections(of: document) }
    }
  }

  /// Progress, at debug level, which the unified log shows while streaming and
  /// doesn't keep.
  private func trace(_ event: String) {
    readerLog.debug("\(self.id.displayName, privacy: .public): \(event, privacy: .public)")
  }
}
