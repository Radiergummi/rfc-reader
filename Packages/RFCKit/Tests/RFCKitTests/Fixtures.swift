import Foundation
import Testing

@testable import RFCKit

enum Fixtures {
  static func data(_ name: String) throws -> Data {
    let url = try #require(
      Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
  }

  static func string(_ name: String) throws -> String {
    String(decoding: try data(name), as: UTF8.self)
  }

  /// Every legacy plain-text fixture, for invariants that must hold across all of them.
  static func legacyTexts() throws -> [String] {
    let directory = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    return try FileManager.default.contentsOfDirectory(atPath: directory.path).filter {
      $0.hasSuffix(".txt")
    }.sorted()
  }

  static func sampleIndex() throws -> RFCIndex {
    try RFCIndexParser.parse(try data("rfc-index-sample.xml"))
  }
}
