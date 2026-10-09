import Benchmark
import Foundation
import RFCKit
import RFCReaderKit

// The work the app waits on, each measured for time, allocations and peak memory:
// the index read at every launch, the search run on every keystroke, and a
// document's parse and build on every open. `make trace` says where the time goes
// in the running app; these pin the pure functions underneath, so a change to one
// is a number against a saved baseline rather than a feeling.
//
// Inputs are real RFCs, read from the directory in `RFC_CORPUS`, which
// `make benchmark` fills: no RFC text is committed (CLAUDE.md). The documents are
// the ones #357 measured: RFC 9110 and 9000, the largest XML the app opens
// often, RFC 5661, the largest legacy text, and RFC 793, a typical one.
//
// Each benchmark runs in a process of its own and reads its input in `setup`,
// which runs before the memory baseline is taken. So a benchmark pays only for
// its own input, and its peak memory is the work's, not the inputs'.
//
// Every benchmark runs its iterations through `iterate`, which drains an
// autorelease pool after each one. Without it, what the work autoreleases is freed
// only when the benchmark ends, and its peak memory grows with the iteration count
// rather than saying what one iteration costs (#420).

let benchmarks: @Sendable () -> Void = {
  Benchmark.defaultConfiguration = .init(
    metrics: [.wallClock, .mallocCountTotal, .peakMemoryResidentDelta],
    maxDuration: .seconds(10),
    maxIterations: 50
  )

  let corpus = Corpus()

  Benchmark("Index: parse") { benchmark, data in
    try iterate(benchmark) {
      blackHole(try RFCIndexParser.parse(data))
    }
  } setup: {
    corpus.data("rfc-index.xml")
  }

  Benchmark("Index: decode snapshot") { benchmark, snapshot in
    try iterate(benchmark) {
      blackHole(try IndexSnapshot.decode(snapshot))
    }
  } setup: {
    try IndexSnapshot.encode(RFCIndexParser.parse(corpus.data("rfc-index.xml")))
  }

  Benchmark("Index: encode snapshot") { benchmark, index in
    try iterate(benchmark) {
      blackHole(try IndexSnapshot.encode(index))
    }
  } setup: {
    try RFCIndexParser.parse(corpus.data("rfc-index.xml"))
  }

  Benchmark("Index: prepare") { benchmark, index in
    iterate(benchmark) {
      blackHole(PreparedIndex(index: index))
    }
  } setup: {
    try RFCIndexParser.parse(corpus.data("rfc-index.xml"))
  }

  for query in ["http", "author:fielding", "transport layer security"] {
    Benchmark("Search: \(query)") { benchmark, search in
      iterate(benchmark) {
        blackHole(search.search(query, limit: .max))
      }
    } setup: {
      IndexSearch(index: try RFCIndexParser.parse(corpus.data("rfc-index.xml")))
    }
  }

  for number in [9110, 9000] {
    Benchmark("Parse XML: RFC \(number)") { benchmark, data in
      try iterate(benchmark) {
        blackHole(try RFCXMLParser.parse(data))
      }
    } setup: {
      corpus.data("rfc\(number).xml")
    }
  }

  for number in [5661, 793] {
    Benchmark("Parse text: RFC \(number)") { benchmark, data in
      iterate(benchmark) {
        blackHole(LegacyTextParser.parse(data))
      }
    } setup: {
      corpus.data("rfc\(number).txt")
    }
  }

  // The reader's column, 712 pt, as #357 measured the builds. RFC 8927 and RFC 8727
  // are mostly source code, so they are what syntax highlighting is measured on;
  // RFC 8727 holds the corpus's largest JSON block, 53 KB.
  let style = ReadingStyle(measure: ReaderLayout.idealMeasure)
  for number in [9110, 9000, 8927, 8727] {
    Benchmark("Build: RFC \(number)") { benchmark, document in
      iterate(benchmark) {
        blackHole(DocumentTextBuilder.build(document, style: style))
      }
    } setup: {
      try RFCXMLParser.parse(corpus.data("rfc\(number).xml"))
    }
  }
  // Every block RFC 8727 highlights, its 53 KB JSON block among them.
  Benchmark("Highlight: RFC 8727") { benchmark, blocks in
    iterate(benchmark) {
      for (text, type) in blocks {
        blackHole(Lexers.highlight(text, as: type))
      }
    }
  } setup: {
    try RFCXMLParser.parse(corpus.data("rfc8727.xml")).blocks.compactMap {
      block -> (String, ArtworkType)? in
      guard case .preformatted(let content) = block,
        let type = ArtworkType.canonical(content.type), Lexers.language(of: type) != nil
      else { return nil }
      return (content.text, type)
    }
  }
  Benchmark("Build: RFC 5661") { benchmark, document in
    iterate(benchmark) {
      blackHole(DocumentTextBuilder.build(document, style: style))
    }
  } setup: {
    LegacyTextParser.parse(corpus.data("rfc5661.txt"))
  }
}

/// Runs `body` once per iteration the benchmark asks for, draining an autorelease
/// pool after each, so what an iteration autoreleases is freed before the next.
func iterate(_ benchmark: Benchmark, _ body: () throws -> Void) rethrows {
  for _ in benchmark.scaledIterations {
    try autoreleasepool(invoking: body)
  }
}

/// The directory the inputs are read from, looked up only when a benchmark's
/// `setup` reads one, so `benchmark list` and the baseline commands run without it.
struct Corpus {
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
