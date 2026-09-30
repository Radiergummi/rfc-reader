import Foundation
import Testing

@testable import RFCKit

enum Fixtures {
  static func data(_ name: String) throws -> Data {
    let url = try #require(
      Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
  }

  /// The fixture parsed as its format is: RFCXML for `.xml`, legacy text otherwise,
  /// decoded as every reader of the format decodes it.
  static func document(_ name: String) throws -> RFCDocument {
    let data = try data(name)
    return name.hasSuffix(".xml") ? try RFCXMLParser.parse(data) : LegacyTextParser.parse(data)
  }

  /// The fixture's text, legacy text decoded as every reader of it decodes it.
  static func string(_ name: String) throws -> String {
    let data = try data(name)
    return name.hasSuffix(".xml")
      ? String(decoding: data, as: UTF8.self) : LegacyTextParser.text(decoding: data)
  }

  /// Every legacy plain-text fixture, for invariants that must hold across all of them.
  static func legacyTexts() throws -> [String] {
    let directory = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    return try FileManager.default.contentsOfDirectory(atPath: directory.path).filter {
      $0.hasSuffix(".txt")
    }.sorted()
  }

  /// Every document fixture, legacy text and RFCXML alike: `rfc<number>.txt` or
  /// `rfc<number>.xml`, which leaves out the index and feed samples beside them.
  static func documents() throws -> [String] {
    let directory = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    return try FileManager.default.contentsOfDirectory(atPath: directory.path).filter {
      $0.wholeMatch(of: #/rfc\d+\.(txt|xml)/#) != nil
    }.sorted()
  }

  static func sampleIndex() throws -> RFCIndex {
    try RFCIndexParser.parse(try data("rfc-index-sample.xml"))
  }
}
