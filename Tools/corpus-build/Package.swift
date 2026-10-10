// swift-tools-version: 6.3
import PackageDescription

// One set of language settings for every target, tests included (#129).
let swiftSettings: [SwiftSetting] = [
  .enableUpcomingFeature("ExistentialAny"),
  .enableUpcomingFeature("MemberImportVisibility"),
  .enableUpcomingFeature("InferIsolatedConformances"),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  // The tree has no warnings, and a new one fails the build (#440). Only these
  // targets, never a dependency.
  .treatAllWarnings(as: .error),
]

// The command line is built unoptimized by a Swift 6.3 or 6.4 compiler, in every
// build. 6.4 crashes while LLVM splits the commands' async `run`s into their coroutine
// parts, and `@_optimize(none)` on them compiles but gives every document of a fetch
// the ID 0 (#371). 6.3, the Linux toolchain, builds them but miscompiles the same way
// without a word: a fetch saves the documents under garbage names, losing most of them,
// and reports success. The work is RFCKit's and RFCCorpusKit's, which stay optimized.
// By the compiler, not the platform, because the bug is the toolchain's; #490 tracks
// dropping this once a toolchain fixes it. A later compiler builds optimized again, so
// one that fixed it is not left unoptimized; #490's check of each new toolchain is what
// says whether it did.
#if compiler(>=6.3) && !compiler(>=6.5)
  let commandLineSettings = swiftSettings + [.unsafeFlags(["-Onone"])]
#else
  let commandLineSettings = swiftSettings
#endif

// Offline pipeline: fetches legacy plain-text RFCs, converts them to RFCXML v3 with
// RFCKit's parsers, and writes a manifest of SHA-256 hashes for the data packs the app
// downloads.
//
// RFCCorpusKit holds what is a pure function of its inputs -- converting one document,
// the report types and the manifest's hashing, the schema check's causes -- so tests
// call it rather than re-implement it. corpus-build is the command line around it:
// arguments, files, concurrency, logging (swift-log) and xmllint.
let package = Package(
  name: "corpus-build",
  // RFCKit's floor.
  platforms: [.macOS(.v26)],
  dependencies: [
    .package(path: "../../Packages/RFCKit"),
    .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.8.2"),
    .package(url: "https://github.com/apple/swift-log", exact: "1.15.1"),
    // SHA-256 for the manifest: CryptoKit on Apple platforms, BoringSSL on Linux.
    .package(url: "https://github.com/apple/swift-crypto", exact: "5.0.0"),
  ],
  targets: [
    .target(
      name: "RFCCorpusKit",
      dependencies: [
        // The system's SQLite, for the index database (#174), as RFCKit has it for
        // the full-text index (#37).
        .product(name: "CSQLite", package: "RFCKit"),
        .product(name: "RFCKit", package: "RFCKit"),
        .product(name: "Crypto", package: "swift-crypto"),
      ],
      swiftSettings: swiftSettings
    ),
    .executableTarget(
      name: "corpus-build",
      dependencies: [
        "RFCCorpusKit",
        .product(name: "RFCKit", package: "RFCKit"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Logging", package: "swift-log"),
      ],
      swiftSettings: commandLineSettings
    ),
    .testTarget(
      name: "RFCCorpusKitTests",
      // corpus-build is here to be built, not imported: the command-line tests run
      // the binary, as `make` does.
      dependencies: [
        "RFCCorpusKit", "corpus-build", .product(name: "RFCKit", package: "RFCKit"),
        .product(name: "CSQLite", package: "RFCKit"),
      ],
      swiftSettings: swiftSettings
    ),
  ],
  swiftLanguageModes: [.v6]
)
