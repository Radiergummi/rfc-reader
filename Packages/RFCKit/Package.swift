// swift-tools-version: 6.3
import PackageDescription

// One set of language settings for every target, tests included (#129).
let swiftSettings: [SwiftSetting] = [
  .enableUpcomingFeature("ExistentialAny"),
  .enableUpcomingFeature("MemberImportVisibility"),
  .enableUpcomingFeature("InferIsolatedConformances"),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  // No treatAllWarnings here, unlike the other packages: RFCKit is their
  // dependency, and Swift 6.3's build system gives a dependency
  // -suppress-warnings, which it refuses beside -warnings-as-errors. Where RFCKit
  // is the root, the Makefile and CI pass -warnings-as-errors instead (#440).
]

let package = Package(
  name: "RFCKit",
  // The app's floors (#129), which its other consumers share: RFCReaderKit declares the
  // same, and corpus-build runs on macOS 26 and Linux. No visionOS until there is a
  // visionOS target.
  platforms: [
    .iOS(.v26),
    .macOS(.v26),
  ],
  products: [
    .library(name: "RFCKit", targets: ["RFCKit"]),
    // For corpus-build, which writes the index database with it, so there is one
    // module of that name in its build.
    .library(name: "CSQLite", targets: ["CSQLite"]),
  ],
  targets: [
    // The system's SQLite: the SDK's on Apple platforms, libsqlite3-dev on Linux.
    // The full-text index is read and written here (#37), so it is tested on Linux.
    .systemLibrary(
      name: "CSQLite",
      pkgConfig: "sqlite3",
      providers: [.apt(["libsqlite3-dev"])]
    ),
    .target(
      name: "RFCKit",
      dependencies: ["CSQLite"],
      // Every unsafe construct the compiler can name is a warning here (#147): the
      // byte scans read `Span`s and the regexes are behind `Pattern` (#146), so the few
      // left are marked `unsafe`, each with its reason, and a new one has to give its own.
      swiftSettings: swiftSettings + [.strictMemorySafety()]
    ),
    .testTarget(
      name: "RFCKitTests",
      // CSQLite for a test that holds a write lock on the index from a connection of its own.
      dependencies: ["RFCKit", "CSQLite"],
      resources: [.copy("Fixtures")],
      swiftSettings: swiftSettings
    ),
  ],
  swiftLanguageModes: [.v6]
)
