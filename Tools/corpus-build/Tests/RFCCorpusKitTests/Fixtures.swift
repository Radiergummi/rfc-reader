import Foundation

/// RFCKit's test fixtures: real RFCs and a sample of the RFC index. SwiftPM shares no
/// resources across packages, so they are found from this file rather than a bundle.
enum Fixtures {
  static let directory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().appending(
      path: "../../../../Packages/RFCKit/Tests/RFCKitTests/Fixtures")

  static func url(_ name: String) -> URL {
    directory.appending(path: name)
  }
}
