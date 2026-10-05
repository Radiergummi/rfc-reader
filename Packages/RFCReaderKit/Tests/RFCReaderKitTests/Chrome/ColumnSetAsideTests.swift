import Testing

@testable import RFCReaderKit

/// The Mac's sidebar and list, collapsed while two documents are compared (#187), and
/// how each is left when the comparison ends.
@Suite struct ColumnSetAsideTests {
  @Test func `a column that was open opens again`() {
    #expect(
      ColumnSetAside(wasCollapsed: false).isCollapsedAfterComparing(isCollapsedNow: true) == false)
  }

  @Test func `a column that was collapsed stays collapsed`() {
    #expect(
      ColumnSetAside(wasCollapsed: true).isCollapsedAfterComparing(isCollapsedNow: true) == true)
  }

  @Test func `a column the reader opened while comparing stays open`() {
    for wasCollapsed in [false, true] {
      #expect(
        ColumnSetAside(wasCollapsed: wasCollapsed).isCollapsedAfterComparing(isCollapsedNow: false)
          == false)
    }
  }
}
