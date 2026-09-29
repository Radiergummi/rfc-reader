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
// Inputs are real RFCs, read from the corpus directory in `RFC_CORPUS`, which
// `make benchmark` fills: no RFC text is committed (CLAUDE.md). The documents are
// the ones #357 measured: RFC 9110 and 9000, the largest XML the app opens
// often, RFC 5661, the largest legacy text, and RFC 793, a typical one.

let benchmarks: @Sendable () -> Void = {
  Benchmark.defaultConfiguration = .init(
    metrics: [.wallClock, .mallocCountTotal, .peakMemoryResident],
    maxDuration: .seconds(10),
    maxIterations: 50
  )

  let corpus = Corpus()

  let indexData = corpus.data("rfc-index.xml")
  Benchmark("Index: parse") { benchmark in
    for _ in benchmark.scaledIterations {
      blackHole(try RFCIndexParser.parse(indexData))
    }
  }

  let index = try! RFCIndexParser.parse(indexData)
  Benchmark("Index: prepare") { benchmark in
    for _ in benchmark.scaledIterations {
      blackHole(PreparedIndex(index: index))
    }
  }

  let search = IndexSearch(index: index)
  for query in ["http", "author:fielding", "transport layer security"] {
    Benchmark("Search: \(query)") { benchmark in
      for _ in benchmark.scaledIterations {
        blackHole(search.search(query, limit: .max))
      }
    }
  }

  for number in [9110, 9000] {
    let data = corpus.data("xml.noindex/rfc\(number).xml")
    Benchmark("Parse XML: RFC \(number)") { benchmark in
      for _ in benchmark.scaledIterations {
        blackHole(try RFCXMLParser.parse(data))
      }
    }
  }

  for number in [5661, 793] {
    let data = corpus.data("text.noindex/rfc\(number).txt")
    Benchmark("Parse text: RFC \(number)") { benchmark in
      for _ in benchmark.scaledIterations {
        blackHole(LegacyTextParser.parse(data))
      }
    }
  }

  // The reader's column, as #357 measured the builds.
  let style = ReadingStyle(measure: 712)
  for number in [9110, 9000] {
    let document = try! RFCXMLParser.parse(corpus.data("xml.noindex/rfc\(number).xml"))
    Benchmark("Build: RFC \(number)") { benchmark in
      for _ in benchmark.scaledIterations {
        blackHole(DocumentTextBuilder.build(document, style: style))
      }
    }
  }
  let legacy = LegacyTextParser.parse(corpus.data("text.noindex/rfc5661.txt"))
  Benchmark("Build: RFC 5661") { benchmark in
    for _ in benchmark.scaledIterations {
      blackHole(DocumentTextBuilder.build(legacy, style: style))
    }
  }
}

/// The corpus directory the inputs are read from.
struct Corpus {
  let directory: URL

  init() {
    guard let path = ProcessInfo.processInfo.environment["RFC_CORPUS"] else {
      fatalError("RFC_CORPUS is not set: run the benchmarks through `make benchmark`")
    }
    directory = URL(filePath: path, directoryHint: .isDirectory)
  }

  func data(_ name: String) -> Data {
    let url = directory.appending(path: name)
    guard let data = try? Data(contentsOf: url) else {
      fatalError("\(url.path) is missing: `make benchmark` fetches it")
    }
    return data
  }
}
