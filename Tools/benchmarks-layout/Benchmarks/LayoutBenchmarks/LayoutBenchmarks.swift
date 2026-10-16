import AppKit
import Benchmark
import Foundation
import RFCKit
import RFCReaderKit

// The reader's TextKit 2 layout, over a built RFC at the reader's column: the whole
// document laid out, a settled jump to the last section, which lays out everything
// above it, one resize step with the line pinned, and one background slice. What
// each of these is in the reader is the viewport-layout decision's,
// docs/decisions/2026-09-30-the-reader-lays-out-its-viewport-and-holds-the-readers-line.md.
//
// Measured for time and peak memory only. These run without package-benchmark's
// malloc interposer, which crashes any TextKit layout (#582), so there is no
// allocation count; Tools/benchmarks keeps them for everything else.
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
    Benchmark("Layout: whole document, RFC \(number)") { benchmark, input async in
      let iterations = benchmark.scaledIterations
      await MainActor.run {
        iterate(iterations) {
          let (layout, _, _) = input.fresh()
          layout.ensureLayout(for: layout.documentRange)
          blackHole(layout.usageBoundsForTextContainer)
        }
      }
    } setup: {
      try LayoutInput(document: corpus.document(file))
    }

    Benchmark("Layout: jump to the last section, RFC \(number)") { benchmark, input async in
      let iterations = benchmark.scaledIterations
      await MainActor.run {
        iterate(iterations) {
          let (layout, surface, target) = input.fresh()
          blackHole(
            PinRecipe.settle(ReaderAnchor(characterOffset: target), in: layout, on: surface))
        }
      }
    } setup: {
      try LayoutInput(document: corpus.document(file))
    }

    Benchmark("Layout: resize step, RFC \(number)") { benchmark, input async in
      let iterations = benchmark.scaledIterations
      await MainActor.run {
        let (layout, surface, target) = input.fresh()
        let anchor = ReaderAnchor(characterOffset: target / 2)
        PinRecipe.pin(anchor, in: layout, on: surface)
        var width = ReaderLayout.idealMeasure
        iterate(iterations) {
          width = width > 320 ? width - 8 : ReaderLayout.idealMeasure
          layout.textContainer?.size = CGSize(width: width, height: 10_000_000)
          blackHole(PinRecipe.pin(anchor, in: layout, on: surface))
        }
      }
    } setup: {
      try LayoutInput(document: corpus.document(file))
    }

    Benchmark("Layout: one background slice, RFC \(number)") { benchmark, input async in
      let iterations = benchmark.scaledIterations
      await MainActor.run {
        let (layout, _, _) = input.fresh()
        var planner = SlicePlanner(length: input.built.text.length)
        iterate(iterations) {
          if planner.isComplete { planner.restart() }
          guard let slice = planner.nextSlice(),
            let range = layout.textRange(for: NSRange(location: 0, length: NSMaxRange(slice)))
          else { return }
          layout.ensureLayout(for: range)
        }
      }
    } setup: {
      try LayoutInput(document: corpus.document(file))
    }
  }
}

/// Runs `body` once per iteration of `iterations` (a benchmark's `scaledIterations`),
/// draining an autorelease pool after each, so what an iteration autoreleases is
/// freed before the next (#420).
///
/// On the main actor, as the reader lays out. The runner calls a benchmark off the
/// main thread, so each one hops there once, with `MainActor.run`, before it starts
/// iterating; the range is taken out first because the benchmark is not `Sendable`.
@MainActor
func iterate(_ iterations: Range<Int>, _ body: () -> Void) {
  for _ in iterations {
    autoreleasepool(invoking: body)
  }
}

/// A built RFC, and a fresh layout of it on demand, so that what a benchmark
/// measures starts from a document nothing has laid out yet.
final class LayoutInput: @unchecked Sendable {
  let built: BuiltDocument
  /// What the last fresh layout needs kept: a layout manager holds its content
  /// storage weakly.
  private var storage: NSTextContentStorage?

  init(document: RFCDocument) {
    built = DocumentTextBuilder.build(
      document, style: ReadingStyle(measure: ReaderLayout.idealMeasure))
  }

  /// A layout of the built text at the reader's column, a surface over it, and the
  /// offset of the document's last section. Installed through `install`, never
  /// `attributedString` (CLAUDE.md).
  @MainActor
  func fresh() -> (NSTextLayoutManager, BenchmarkSurface, Int) {
    let storage = NSTextContentStorage()
    let layout = NSTextLayoutManager()
    let container = NSTextContainer(
      size: CGSize(width: ReaderLayout.idealMeasure, height: 10_000_000))
    container.lineFragmentPadding = 0
    layout.textContainer = container
    storage.addTextLayoutManager(layout)
    storage.install(built.text)
    self.storage = storage
    let target = built.anchors.sections.entries.last?.offset ?? 0
    return (layout, BenchmarkSurface(layout: layout), target)
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
