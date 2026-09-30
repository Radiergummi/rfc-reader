import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

enum Fixtures {
  static func data(_ name: String) throws -> Data {
    let url = try #require(
      Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
  }

  /// One of RFCKit's committed fixtures, read where it is. Never copy one into this
  /// package: no RFC text is committed twice.
  static func rfcKitData(_ name: String) throws -> Data {
    let directory = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("../../../RFCKit/Tests/RFCKitTests/Fixtures")
      .standardizedFileURL
    return try Data(contentsOf: directory.appendingPathComponent(name))
  }

  /// RFCXML v3: structured sections, tables, cross references with derivedContent.
  static func rfc8999() throws -> RFCDocument {
    try RFCXMLParser.parse(try data("rfc8999.xml"))
  }

  /// Legacy plain text: structure recovered heuristically, labels verbatim.
  static func rfc2119() throws -> RFCDocument {
    LegacyTextParser.parse(try data("rfc2119.txt"))
  }

  /// A committed fixture, parsed by its extension: this package's own where it has
  /// one by that name, RFCKit's otherwise.
  static func document(named name: String) throws -> RFCDocument {
    let data =
      Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") != nil
      ? try data(name) : try rfcKitData(name)
    return name.hasSuffix(".xml") ? try RFCXMLParser.parse(data) : LegacyTextParser.parse(data)
  }

  /// An index entry for RFC `number` with only the fields a test sets; the rest are
  /// the index's own defaults.
  static func metadata(
    _ number: Int, title: String = "Title", year: Int = 2020, month: Int? = nil,
    obsoletedBy: [DocumentID] = [], currentStatus: PublicationStatus = .unknown,
    stream: PublicationStream = .legacy, workingGroup: String? = nil
  ) -> RFCMetadata {
    RFCMetadata(
      id: .rfc(number), title: title, date: PublicationDate(year: year, month: month),
      obsoletedBy: obsoletedBy, currentStatus: currentStatus, stream: stream,
      workingGroup: workingGroup)
  }

  /// A one-section document around `blocks` — the shell almost every builder test
  /// needs and none of them is testing.
  static func document(_ blocks: Block...) -> RFCDocument {
    RFCDocument(
      header: DocumentHeader(title: "T"),
      sections: [Section(anchor: "section-1", number: "1", title: "S", blocks: blocks)],
      source: .xml
    )
  }

  /// Where `needle` starts, in the UTF-16 offsets `NSAttributedString.attribute(at:)`
  /// is indexed by. `String.distance` counts Characters, which is the same number
  /// only while the text stays in the BMP with no combining marks — not a property
  /// of RFCs worth relying on once per assertion.
  static func offset(of needle: String, in text: NSAttributedString) throws -> Int {
    let found = (text.string as NSString).range(of: needle)
    try #require(found.location != NSNotFound, "\(needle) is not in the storage")
    return found.location
  }

  /// One run of inlines, rendered against the body font.
  static func inlineRun(_ inlines: [Inline], style: ReadingStyle = ReadingStyle())
    -> NSAttributedString
  {
    DocumentTextBuilder(style: style).inlineRuns(inlines, base: [.font: style.bodyFont])
  }
}

/// A font as a failure message names it: its PostScript name, size and symbolic
/// traits, which tell a fallback face from a system face at the wrong size (#326).
func describe(_ font: PlatformFont) -> String {
  "\(font.fontName) \(font.pointSize) pt, traits 0x\(String(font.fontDescriptor.symbolicTraits.rawValue, radix: 16))"
}
