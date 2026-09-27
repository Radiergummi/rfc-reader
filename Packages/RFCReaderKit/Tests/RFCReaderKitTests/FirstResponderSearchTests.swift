#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit
  import Testing
  @testable import RFCReaderKit

  /// A stand-in for the views that do and do not want focus: SwiftUI's list view
  /// accepts, the cell hosting views inside it do not.
  private final class Taker: NSView {
    override var acceptsFirstResponder: Bool { true }
  }

  @Suite("First responder search")
  @MainActor
  struct FirstResponderSearchTests {
    /// root
    ///   column        (takes nothing)
    ///     list        (takes it)
    ///       cell      (takes nothing) <- the click lands here
    @MainActor
    private struct Tree {
      let root = NSView()
      let list = Taker()
      let cell = NSView()

      init() {
        let column = NSView()
        list.addSubview(cell)
        column.addSubview(list)
        root.addSubview(column)
      }
    }

    @Test func `a click on a cell focuses the list around it`() {
      let views = Tree()
      let found = FirstResponderSearch.target(from: views.cell, upTo: views.root, skipping: nil)
      #expect(found === views.list)
    }

    @Test func `a click inside what already has focus changes nothing`() {
      let views = Tree()
      let found = FirstResponderSearch.target(
        from: views.cell, upTo: views.root, skipping: views.list)
      #expect(found == nil)
    }

    @Test func `a click with nothing above it that takes focus is refused`() {
      let root = NSView()
      let column = NSView()
      let cell = NSView()
      column.addSubview(cell)
      root.addSubview(column)
      #expect(FirstResponderSearch.target(from: cell, upTo: root, skipping: nil) == nil)
    }

    /// The walk stops at the root rather than escaping into whatever contains it,
    /// which on a real window is the titlebar's sibling and then the window itself.
    @Test func `the walk stops at the root even when something above it would take focus`() {
      let outside = Taker()
      let root = NSView()
      let cell = NSView()
      root.addSubview(cell)
      outside.addSubview(root)
      #expect(FirstResponderSearch.target(from: cell, upTo: root, skipping: nil) == nil)
    }

    @Test func `a hit that itself takes focus is the answer`() {
      let views = Tree()
      let found = FirstResponderSearch.target(from: views.list, upTo: views.root, skipping: nil)
      #expect(found === views.list)
    }

    @Test func `the innermost search reaches past a container that would take it first`() {
      let column = Taker()
      let list = Taker()
      column.addSubview(list)
      // Asked from the top, `column` answers yes — which is exactly the hosting
      // view answering for its content, and the wrong answer.
      #expect(FirstResponderSearch.innermostTarget(in: column) === list)
    }

    @Test func `the innermost search falls back to the root itself`() {
      let column = Taker()
      column.addSubview(NSView())
      #expect(FirstResponderSearch.innermostTarget(in: column) === column)
    }

    /// The case `placeInitialFocus` retries for: a column whose list SwiftUI has not
    /// built yet has nothing to focus, and the caller must be able to tell.
    @Test func `an empty column has nothing to focus`() {
      let column = NSView()
      column.addSubview(NSView())
      #expect(FirstResponderSearch.innermostTarget(in: column) == nil)
    }
  }
#endif
