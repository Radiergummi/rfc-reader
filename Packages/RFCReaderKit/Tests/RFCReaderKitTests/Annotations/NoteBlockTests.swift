import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What a block's context menu puts a note on (#523), over a committed fixture.
@Suite("Annotations: a note on a block")
struct NoteBlockTests {
  private let built: BuiltDocument

  init() throws {
    built = DocumentTextBuilder.build(try Fixtures.document(named: "rfc9290.xml"), style: ReadingStyle())
  }

  private var text: NSString { built.text.string as NSString }

  private func covered(_ block: NoteBlock?) -> String? {
    guard let block, let range = block.target.range(in: built.positions.model) else { return nil }
    return built.positions.model.text(in: range)
  }

  @Test func `a paragraph's note covers the paragraph`() throws {
    let location = text.range(of: "problem details").location
    try #require(location != NSNotFound)
    let block = NoteBlock(at: location, in: built)
    guard case .paragraph? = block else {
      Issue.record("not a paragraph: \(String(describing: block))")
      return
    }
    // The whole paragraph, as the model has it, and no more: up to its line end.
    let range = try #require(block?.target.range(in: built.positions.model))
    let model = built.positions.model
    #expect(model.text(in: range).hasPrefix("This document defines a concise"))
    #expect(!model.text(in: range).contains("\n"))
    #expect(model.text(in: range.upperBound..<range.upperBound + 1) == "\n")
  }

  @Test func `a figure's note covers the whole figure`() throws {
    var location = NSNotFound
    built.text.enumerateAttribute(
      .rfcVerbatim, in: NSRange(location: 0, length: built.text.length)
    ) { value, range, stop in
      if value != nil {
        location = range.location + range.length / 2
        stop.pointee = true
      }
    }
    try #require(location != NSNotFound)
    let block = NoteBlock(at: location, in: built)
    guard case .figure? = block else {
      Issue.record("not a figure: \(String(describing: block))")
      return
    }
    #expect((covered(block)?.count ?? 0) > 40)
  }

  @Test func `a heading's note is on its section`() throws {
    var location = NSNotFound
    var anchor: String?
    built.text.enumerateAttribute(
      .rfcAnchor, in: NSRange(location: 0, length: built.text.length)
    ) { value, range, stop in
      if let value = value as? String, value != ModelText.abstractAnchor {
        location = range.location
        anchor = value
        stop.pointee = true
      }
    }
    try #require(location != NSNotFound)
    #expect(NoteBlock(at: location, in: built) == .section(try #require(anchor)))
  }
}
