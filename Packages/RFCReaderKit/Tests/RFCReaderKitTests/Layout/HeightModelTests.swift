import Foundation
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The document's height as the scroller sees it: estimated per paragraph from
/// what the builder measured, and exact wherever TextKit has laid a paragraph out.
@Suite("Height model")
@MainActor
struct HeightModelTests {
  @Test func `the builder measures one entry per paragraph`() throws {
    let built = try LayoutFixture.built()
    let string = built.text.string as NSString
    var paragraphs = 0
    string.enumerateSubstrings(
      in: NSRange(location: 0, length: string.length),
      options: [.byParagraphs, .substringNotRequired]
    ) { _, _, _, _ in paragraphs += 1 }
    #expect(built.paragraphs.count == paragraphs)
    #expect(built.paragraphs.map(\.length).reduce(0, +) == built.text.length)
  }

  /// The probe's crude model was within 6%; the measured one must do better.
  @Test(arguments: [712.0, 320.0])
  func `the estimate is within five percent of the laid-out height`(column: CGFloat) throws {
    let built = try LayoutFixture.built(measure: column)
    let fixture = LayoutFixture(text: built.text, width: column)
    fixture.layout.ensureLayout(for: fixture.layout.documentRange)
    let truth = fixture.layout.usageBoundsForTextContainer.height
    let model = HeightModel(paragraphs: built.paragraphs, column: column)
    #expect(abs(model.total - truth) / truth < 0.05, "estimate \(model.total), truth \(truth)")
  }

  @Test func `measuring every paragraph makes the model exact`() throws {
    let built = try LayoutFixture.built()
    let fixture = LayoutFixture(text: built.text, width: 712)
    fixture.layout.ensureLayout(for: fixture.layout.documentRange)
    var model = HeightModel(paragraphs: built.paragraphs, column: 712)
    var heights: [(paragraph: Int, height: CGFloat)] = []
    fixture.layout.enumerateTextLayoutFragments(
      from: fixture.layout.documentRange.location, options: []
    ) {
      heights.append(
        (
          model.paragraph(containing: fixture.layout.offset(of: $0.rangeInElement.location)),
          $0.layoutFragmentFrame.height
        ))
      return true
    }
    model.measure(heights)
    #expect(abs(model.total - fixture.layout.usageBoundsForTextContainer.height) < 1)
  }

  @Test func `a paragraph's top finds the paragraph again`() throws {
    let model = HeightModel(paragraphs: try LayoutFixture.built().paragraphs, column: 712)
    for index in stride(from: 0, to: model.count, by: 7) {
      #expect(model.paragraph(atHeight: model.top(ofParagraph: index)) == index)
      #expect(model.paragraph(containing: model.characterOffset(ofParagraph: index)) == index)
    }
  }

  @Test func `the ends of the model are its first and last paragraphs`() throws {
    let model = HeightModel(paragraphs: try LayoutFixture.built().paragraphs, column: 712)
    #expect(model.paragraph(atHeight: -50) == 0)
    #expect(model.paragraph(atHeight: model.total) == model.count - 1)
    #expect(model.paragraph(atHeight: model.total + 500) == model.count - 1)
  }

  @Test func `an empty document has no height and answers for paragraph zero`() {
    let model = HeightModel(paragraphs: [], column: 712)
    #expect(model.total == 0)
    #expect(model.paragraph(atHeight: 100) == 0)
    #expect(model.paragraph(containing: 0) == 0)
  }

  @Test func `a narrower column estimates a taller document`() throws {
    var model = HeightModel(paragraphs: try LayoutFixture.built().paragraphs, column: 712)
    let wide = model.total
    model.setColumn(320)
    #expect(model.total > wide)
  }
}
