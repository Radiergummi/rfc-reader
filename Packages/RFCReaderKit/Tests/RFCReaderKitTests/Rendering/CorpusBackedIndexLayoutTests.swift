import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The six RFCXML documents with an index, set by the reader: a letter per group,
/// where its anchor lands, and every locator a link to a place the build holds.
@Suite("Corpus-backed: index layout", .enabled(if: CorpusXML.isAvailable))
struct CorpusBackedIndexLayoutTests {
  static let documents = ["rfc9051", "rfc9110", "rfc9111", "rfc9112", "rfc9114", "rfc9499"]

  @Test(arguments: documents)
  func `the map has a letter per group, where the group's anchor lands`(stem: String) throws {
    let document = try CorpusXML.document(stem)
    let index = try #require(
      document.blocks.lazy.compactMap { block -> IndexBlock? in
        if case .index(let index) = block { index } else { nil }
      }.first)
    let built = DocumentTextBuilder.build(document, style: ReadingStyle())
    let map = built.indexMap
    #expect(map.groups.map(\.anchor) == index.groups.map(\.anchor))
    for group in map.groups {
      #expect(
        built.anchors.offset(of: group.anchor) == group.labelRange.location, "\(group.anchor)")
    }
    #expect(map.entries.count == index.groups.reduce(0) { $0 + $1.entries.count })
  }

  @Test(arguments: documents)
  func `every locator is a link to an anchor the build holds`(stem: String) throws {
    let built = DocumentTextBuilder.build(try CorpusXML.document(stem), style: ReadingStyle())
    let map = built.indexMap
    var links = 0
    built.text.enumerateAttribute(.link, in: map.range) { value, _, _ in
      guard let url = value as? URL else { return }
      links += 1
      let anchor = DocumentTextBuilder.anchor(from: url)
      #expect(anchor.flatMap { built.anchors.offset(of: $0) } != nil, "\(stem): \(url)")
    }
    #expect(links > 0)
  }

  @Test(arguments: documents)
  func `no locator keeps prep's long label`(stem: String) throws {
    let built = DocumentTextBuilder.build(try CorpusXML.document(stem), style: ReadingStyle())
    let index = (built.text.string as NSString).substring(with: built.indexMap.range)
    #expect(!index.contains("Section "))
    #expect(!index.contains(", Paragraph "))
  }
}
