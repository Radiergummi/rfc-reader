import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// Which column a collapsed split view shows, and what going back to one clears
/// (#256).
@Suite("Compact column")
struct CompactColumnTests {
  /// A deep link opens a document whichever column is on screen, so the column
  /// follows the state rather than the last tap.
  @Test(arguments: [
    (true, true, CompactColumn.detail),
    (true, false, .detail),
    (false, true, .content),
    (false, false, .sidebar),
  ])
  func `the column shows the deepest thing chosen`(
    document: Bool, filter: Bool, column: CompactColumn
  ) {
    #expect(CompactColumn.showing(document: document, filter: filter) == column)
  }

  /// Back from the document hides it, and the list stays on its filter.
  @Test func `going back to the list hides the document`() {
    let cleared = CompactColumn.content.clears
    #expect(cleared.document)
    #expect(!cleared.filter)
  }

  /// Back to the sidebar leaves no filter selected there, or it reads as a tap
  /// left behind, and no document shown behind it.
  @Test func `going back to the sidebar clears both`() {
    let cleared = CompactColumn.sidebar.clears
    #expect(cleared.document)
    #expect(cleared.filter)
  }

  @Test func `the document clears nothing`() {
    let cleared = CompactColumn.detail.clears
    #expect(!cleared.document)
    #expect(!cleared.filter)
  }

  /// Whatever the state, the column it maps to clears nothing of it: setting the
  /// column from the state never undoes the state.
  @Test(arguments: [(true, true), (true, false), (false, true), (false, false)])
  func `a column set from the state keeps the state`(document: Bool, filter: Bool) {
    let cleared = CompactColumn.showing(document: document, filter: filter).clears
    #expect(!(document && cleared.document))
    #expect(!(filter && cleared.filter))
  }
}
