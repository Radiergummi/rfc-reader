// swift-tools-version: 6.3
import PackageDescription

// The same language settings as RFCKit and RFCReaderKit, so the benchmarks
// compile under the rules of the code they measure.
let swiftSettings: [SwiftSetting] = [
  .enableUpcomingFeature("ExistentialAny"),
  .enableUpcomingFeature("MemberImportVisibility"),
  .enableUpcomingFeature("InferIsolatedConformances"),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

// Benchmarks for the work the app waits on: parsing the index and documents,
// searching, and building a document's text. A package of its own, so neither
// RFCKit nor RFCReaderKit takes on package-benchmark as a dependency, and the
// Linux CI job never resolves it. Run with `make benchmark`, which fetches the
// inputs; see Benchmarks/RFCBenchmarks/RFCBenchmarks.swift.
let package = Package(
  name: "benchmarks",
  platforms: [
    .macOS(.v26)
  ],
  dependencies: [
    .package(url: "https://github.com/ordo-one/package-benchmark", exact: "1.36.2"),
    .package(path: "../../Packages/RFCKit"),
    .package(path: "../../Packages/RFCReaderKit"),
  ],
  targets: [
    .executableTarget(
      name: "RFCBenchmarks",
      dependencies: [
        .product(name: "Benchmark", package: "package-benchmark"),
        .product(name: "RFCKit", package: "RFCKit"),
        .product(name: "RFCReaderKit", package: "RFCReaderKit"),
      ],
      path: "Benchmarks/RFCBenchmarks",
      swiftSettings: swiftSettings,
      plugins: [
        .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
      ]
    )
  ],
  swiftLanguageModes: [.v6]
)
