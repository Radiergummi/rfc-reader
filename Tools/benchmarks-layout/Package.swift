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

// Benchmarks of the reader's TextKit 2 layout. A package of their own, beside
// Tools/benchmarks, because package-benchmark's malloc interposer crashes any
// TextKit layout (#582, ordo-one/malloc-interposer#9): it is off here, which
// costs these benchmarks their allocation counts, and only these. `make benchmark`
// runs both packages; see Benchmarks/LayoutBenchmarks/LayoutBenchmarks.swift.
let package = Package(
  name: "benchmarks-layout",
  platforms: [
    .macOS(.v26)
  ],
  dependencies: [
    // No traits: the default ones include the malloc interposer.
    .package(url: "https://github.com/ordo-one/package-benchmark", exact: "1.38.0", traits: []),
    .package(path: "../../Packages/RFCKit"),
    .package(path: "../../Packages/RFCReaderKit"),
  ],
  targets: [
    .executableTarget(
      name: "LayoutBenchmarks",
      dependencies: [
        .product(name: "Benchmark", package: "package-benchmark"),
        .product(name: "RFCKit", package: "RFCKit"),
        .product(name: "RFCReaderKit", package: "RFCReaderKit"),
      ],
      path: "Benchmarks/LayoutBenchmarks",
      swiftSettings: swiftSettings,
      plugins: [
        .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
      ]
    )
  ],
  swiftLanguageModes: [.v6]
)
