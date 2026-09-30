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

  // MARK: - The knob

  @Test func `the knob is at the start at the top and at the end at the last screen`() throws {
    let model = HeightModel(paragraphs: try LayoutFixture.built().paragraphs, column: 712)
    let top = try #require(model.knob(paragraph: 0, within: 0, visible: 900, shown: model.total))
    #expect(top.position == 0)
    #expect(abs(top.proportion - 900 / model.total) < 0.0001)
    let end = try #require(
      model.knob(paragraph: model.count - 1, within: 10_000, visible: 900, shown: model.total))
    #expect(end.position == 1)
  }

  /// Review focus: a one-page RFC. Nothing to scroll, so the knob fills the track,
  /// and no division by the zero-height range.
  @Test func `a document shorter than the viewport fills the track`() throws {
    let model = HeightModel(paragraphs: try LayoutFixture.built().paragraphs, column: 712)
    let knob = try #require(
      model.knob(paragraph: 3, within: 0, visible: model.total * 2, shown: model.total))
    #expect(knob.proportion == 1)
    #expect(knob.position.isFinite)
    let target = model.target(atFraction: 1, visible: model.total * 2, shown: model.total)
    #expect(target.paragraph == 0 && target.within == 0)
  }

  @Test func `an empty model has no knob`() {
    let model = HeightModel(paragraphs: [], column: 712)
    #expect(model.knob(paragraph: 0, within: 0, visible: 900, shown: 0) == nil)
  }

  /// Dragging the knob and reading it back agree, so the knob does not jump away
  /// from under the pointer once the jump lands.
  @Test(arguments: [0.0, 0.1, 0.37, 0.5, 0.93, 1.0])
  func `a fraction the knob is dragged to reads back as that fraction`(fraction: Double) throws {
    let model = HeightModel(paragraphs: try LayoutFixture.built().paragraphs, column: 712)
    let target = model.target(atFraction: fraction, visible: 900, shown: model.total)
    let knob = try #require(
      model.knob(
        paragraph: target.paragraph, within: target.within, visible: 900, shown: model.total))
    #expect(abs(knob.position - fraction) < 0.0001)
  }
}
