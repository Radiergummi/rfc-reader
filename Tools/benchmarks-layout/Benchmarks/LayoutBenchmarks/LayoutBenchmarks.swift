import AppKit
import Benchmark
import Foundation
import RFCKit
import RFCReaderKit

// The reader's TextKit 2 layout, over a built RFC at the reader's column: a settled
// jump to the last section, which lays out everything above it; one resize step
// with the line pinned; and one background slice. What each of these is in the
// reader is the viewport-layout decision's,
// docs/decisions/2026-09-30-the-reader-lays-out-its-viewport-and-holds-the-readers-line.md.
//
// Measured for time and peak memory only. These run without package-benchmark's
// malloc interposer, which crashes any TextKit layout (#582), so there is no
// allocation count; Tools/benchmarks keeps them for everything else.
//
// A sample is one call of a benchmark's closure, and each measures one step: what
// the step needs first (a fresh layout, a pinned line, the slices before it) is made
// before `startMeasurement`, so neither installing the text nor the layout's setup
// is in the number. The runner calls a benchmark off the main thread, and the layout
// is the main actor's, as it is in the reader, so the step is one `MainActor.run`
// hop, whose few microseconds are in every sample.
//
// Inputs are real RFCs, read from the directory in `RFC_CORPUS`, which
// `make benchmark` fills: no RFC text is committed (CLAUDE.md). RFC 9000 is the
// largest XML the app opens often, and RFC 5661 the largest legacy text.

let benchmarks: @Sendable () -> Void = {
  Benchmark.defaultConfiguration = .init(
    metrics: [.wallClock, .peakMemoryResidentDelta],
    maxDuration: .seconds(10),
    maxIterations: 50
  )

  let corpus = Corpus()

  for (number, file) in [(9000, "rfc9000.xml"), (5661, "rfc5661.txt")] {
    // From a document nothing has laid out, as a jump from the contents panel
    // right after opening it.
    Benchmark("Layout: jump to the last section, RFC \(number)") { benchmark, input async in
      await MainActor.run { input.layOutAfresh() }
      benchmark.startMeasurement()
      blackHole(await MainActor.run { autoreleasepool { input.jumpToLastSection() } })
    } setup: {
      try LayoutInput(document: corpus.document(file))
    }

    // One step of a live resize: the column 8 pt narrower, down to 320 and back up
    // to the reader's, with the line in the middle of the document kept on top.
    Benchmark("Layout: resize step, RFC \(number)") { benchmark, input async in
      await MainActor.run { input.prepareResizing() }
      benchmark.startMeasurement()
      blackHole(await MainActor.run { autoreleasepool { input.resizeStep() } })
    } setup: {
      try LayoutInput(document: corpus.document(file))
    }

    // The next 6,000 characters of background completion, after the ones before
    // them, as the reader lays them out one frame at a time.
    Benchmark("Layout: one background slice, RFC \(number)") { benchmark, input async in
      await MainActor.run { input.prepareSlicing() }
      benchmark.startMeasurement()
      await MainActor.run { autoreleasepool { input.layOutNextSlice() } }
    } setup: {
      try LayoutInput(document: corpus.document(file))
    }
  }
}

/// A built RFC, and the layout of it that a benchmark's samples work on.
///
/// `@unchecked Sendable` because a benchmark hands it from its setup to its closure,
/// and the closure touches it only on the main actor; each benchmark runs in a
/// process of its own, so no two benchmarks share one.
final class LayoutInput: @unchecked Sendable {
  private static let widest = ReaderLayout.idealMeasure
  private static let narrowest: CGFloat = 320
  private static let resizeStep: CGFloat = 8

  let built: BuiltDocument
  /// Where the last section starts, which a jump goes to.
  private let lastSection: Int
  private var current: Layout?
  private var width = widest
  private var slices: SlicePlanner?

  init(document: RFCDocument) {
    built = DocumentTextBuilder.build(document, style: ReadingStyle(measure: Self.widest))
    lastSection = built.anchors.sections.entries.last?.offset ?? 0
  }

  /// A new layout of the built text, nothing of it laid out yet. The one it replaces
  /// is released here, before the measurement, not in a sample.
  @MainActor
  func layOutAfresh() {
    current = nil
    current = Layout(built.text, width: Self.widest)
  }

  @MainActor
  func jumpToLastSection() -> Int {
    guard let current else { preconditionFailure("layOutAfresh first") }
    return PinRecipe.settle(
      ReaderAnchor(characterOffset: lastSection), in: current.layout, on: current.surface)
  }

  /// The layout, with the line half way down the document pinned, once: the warmup's
  /// sample makes it, and every sample after resizes the same layout further.
  @MainActor
  func prepareResizing() {
    guard current == nil else { return }
    layOutAfresh()
    resizeStep()
  }

  @MainActor
  @discardableResult
  func resizeStep() -> Int {
    guard let current else { preconditionFailure("prepareResizing first") }
    width = width - Self.resizeStep < Self.narrowest ? Self.widest : width - Self.resizeStep
    current.layout.textContainer?.size = CGSize(width: width, height: 10_000_000)
    return PinRecipe.pin(
      ReaderAnchor(characterOffset: lastSection / 2), in: current.layout, on: current.surface)
  }

  /// A fresh layout and planner the first time, and again once every slice is laid
  /// out, so that a sample always lays out a slice nothing has laid out yet.
  @MainActor
  func prepareSlicing() {
    guard slices == nil || slices?.isComplete == true else { return }
    layOutAfresh()
    slices = SlicePlanner(length: built.text.length)
  }

  @MainActor
  func layOutNextSlice() {
    guard let current, let slice = slices?.nextSlice(),
      let range = current.layout.textRange(
        for: NSRange(location: 0, length: NSMaxRange(slice)))
    else { preconditionFailure("prepareSlicing first") }
    current.layout.ensureLayout(for: range)
  }
}

/// A text laid out headless at a column: the content storage, kept because the
/// layout manager holds it weakly, the layout manager and a surface over it.
/// Installed through `install`, never `attributedString` (CLAUDE.md).
@MainActor
struct Layout {
  let storage = NSTextContentStorage()
  let layout = NSTextLayoutManager()
  let surface: BenchmarkSurface

  init(_ text: NSAttributedString, width: CGFloat) {
    let container = NSTextContainer(size: CGSize(width: width, height: 10_000_000))
    container.lineFragmentPadding = 0
    layout.textContainer = container
    storage.addTextLayoutManager(layout)
    storage.install(text)
    surface = BenchmarkSurface(layout: layout)
  }
}

/// A scroll view without a view: a top, and a viewport of a window's height that
/// lays out what it covers, as `ReaderLayoutEngine` asks of a text view.
@MainActor
final class BenchmarkSurface: PinSurface {
  private static let viewportHeight: CGFloat = 900
  let layout: NSTextLayoutManager
  var containerTop: CGFloat = 0

  init(layout: NSTextLayoutManager) {
    self.layout = layout
  }

  func scroll(toContainerY target: CGFloat) {
    containerTop = max(0, target)
  }

  func layOutViewport() {
    let top = containerTop
    guard let first = layout.textLayoutFragment(for: CGPoint(x: 0, y: top)) else { return }
    layout.enumerateTextLayoutFragments(
      from: first.rangeInElement.location, options: [.ensuresLayout]
    ) { fragment in
      fragment.layoutFragmentFrame.minY < top + Self.viewportHeight
    }
  }
}

/// The directory the inputs are read from, looked up only when a benchmark's
/// `setup` reads one, so `benchmark list` and the baseline commands run without it.
struct Corpus {
  /// The document in `name`: RFCXML, or a legacy RFC's text, parsed as the app
  /// parses each.
  func document(_ name: String) throws -> RFCDocument {
    let data = data(name)
    return name.hasSuffix(".txt") ? LegacyTextParser.parse(data) : try RFCXMLParser.parse(data)
  }

  func data(_ name: String) -> Data {
    guard let path = ProcessInfo.processInfo.environment["RFC_CORPUS"] else {
      fatalError("RFC_CORPUS is not set: run the benchmarks through `make benchmark`")
    }
    let url = URL(filePath: path, directoryHint: .isDirectory).appending(path: name)
    do {
      return try Data(contentsOf: url)
    } catch {
      fatalError("\(url.path) cannot be read (`make benchmark` fetches it): \(error)")
    }
  }
}
