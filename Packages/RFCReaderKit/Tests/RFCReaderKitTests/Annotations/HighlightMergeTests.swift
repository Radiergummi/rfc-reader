import Foundation
import Testing

@testable import RFCReaderKit

@Suite("Annotations: merging highlights")
struct HighlightMergeTests {
  private let old = UUID()
  private let newer = UUID()
  private let newest = UUID()

  @Test func `nothing overlapping makes a new highlight`() {
    let plan = HighlightMerge.plan(
      adding: 10..<20,
      to: [HighlightMerge.Existing(identifier: old, range: 0..<10, createdAt: .distantPast)])
    #expect(plan == HighlightMerge.Plan(survivor: nil, absorbed: [], range: 10..<20))
  }

  @Test func `the oldest of several survives, covering them all`() {
    let plan = HighlightMerge.plan(
      adding: 8..<32,
      to: [
        HighlightMerge.Existing(identifier: newest, range: 30..<40, createdAt: .now),
        HighlightMerge.Existing(identifier: old, range: 5..<10, createdAt: .distantPast),
        HighlightMerge.Existing(
          identifier: newer, range: 12..<14, createdAt: .now.addingTimeInterval(-60)),
      ])
    #expect(plan.survivor == old)
    #expect(plan.absorbed == [newer, newest])
    #expect(plan.range == 5..<40)
  }
}
