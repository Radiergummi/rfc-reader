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

  // MARK: What a pane has to show (#325)

  /// A document the index describes has its Info while its body is still loading,
  /// or failed to load, or was offline; its contents and references come with the
  /// body.
  @Test func `with only the index, Info has content and the lists have none`() {
    #expect(InspectorPane.hasContent(.info, hasBody: false, isDescribed: true))
    #expect(!InspectorPane.hasContent(.navigation, hasBody: false, isDescribed: true))
  }

  @Test func `with the body, every pane has content`() {
    #expect(InspectorPane.hasContent(.info, hasBody: true, isDescribed: true))
    #expect(InspectorPane.hasContent(.navigation, hasBody: true, isDescribed: true))
  }

  /// A document the index does not know has no Info to show until its body says
  /// what it is.
  @Test func `with neither, no pane has content`() {
    #expect(!InspectorPane.hasContent(.info, hasBody: false, isDescribed: false))
    #expect(!InspectorPane.hasContent(.navigation, hasBody: false, isDescribed: false))
  }

  // MARK: What the navigation pane shows without the body (#325)

  /// A load under way shows progress, as the requirements tab does while it
  /// extracts, rather than saying the document has not loaded.
  @Test func `while the body is loading, the lists show progress`() {
    #expect(InspectorPane.navigationContent(hasBody: false, isLoading: true) == .loading)
  }

  /// A load that failed, or was offline, is over: nothing more is coming.
  @Test func `once a load has failed, the lists say the document has not loaded`() {
    #expect(InspectorPane.navigationContent(hasBody: false, isLoading: false) == .notLoaded)
  }

  @Test func `with the body, the lists show`() {
    #expect(InspectorPane.navigationContent(hasBody: true, isLoading: false) == .lists)
  }
}
