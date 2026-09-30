import Testing

@testable import RFCReaderKit

/// The inspector's two panes share one slot, as Pages' Format and Document do: each
/// has its own toolbar button, and the buttons swap the slot's content (#25).
@Suite("Inspector pane")
struct InspectorPaneTests {
  @Test func `a button opens a closed inspector on its own pane`() {
    let result = InspectorPane.pressing(.info, isOpen: false, showing: .navigation)
    #expect(result.isOpen)
    #expect(result.pane == .info)
  }

  @Test func `the other button swaps the pane and leaves it open`() {
    let result = InspectorPane.pressing(.info, isOpen: true, showing: .navigation)
    #expect(result.isOpen)
    #expect(result.pane == .info)
  }

  /// And keeps the pane, so the next open shows what was last there.
  @Test func `a button closes the inspector showing its own pane`() {
    let result = InspectorPane.pressing(.navigation, isOpen: true, showing: .navigation)
    #expect(!result.isOpen)
    #expect(result.pane == .navigation)
  }
}
