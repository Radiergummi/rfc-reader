import Testing

@testable import RFCReaderKit

/// One owner for how far the document's title has come into the toolbar (#281): the
/// title shows unless a reader with a header on screen says otherwise, and while a
/// document loads its header counts as pending.
@Suite("Toolbar title ownership")
struct ToolbarTitleOwnershipTests {
  private final class Reader {}
  private let first = ObjectIdentifier(Reader.self)
  private let second = ObjectIdentifier(Int.self)
  private let halfway = ToolbarTitleState(reveal: 0.5, runningHeading: .steady(nil))

  @Test func `with no reader and nothing loading the title shows`() {
    #expect(ToolbarTitleOwnership().state == .shown)
  }

  /// Loading counts as a header pending, so the title stays out of the toolbar
  /// rather than flashing in before the new document's header appears.
  @Test func `while a document loads the title is hidden`() {
    var ownership = ToolbarTitleOwnership()
    ownership.beginLoading()
    #expect(ownership.state == .hidden)
  }

  /// Between the load finishing and the reader's first report, the header is still
  /// pending: the title does not show for a moment and then drop.
  @Test func `the header stays pending until the reader reports`() {
    var ownership = ToolbarTitleOwnership()
    ownership.beginLoading()
    ownership.report(halfway, from: first)
    #expect(ownership.state == halfway)
  }

  /// A failed load has no header, and the toolbar names the RFC that failed.
  @Test func `a failed load shows the title`() {
    var ownership = ToolbarTitleOwnership()
    ownership.beginLoading()
    ownership.failLoading()
    #expect(ownership.state == .shown)
  }

  /// The original text has no header, whatever the rendered document behind it
  /// is doing.
  @Test func `the original text shows the title`() {
    var ownership = ToolbarTitleOwnership()
    ownership.beginLoading()
    ownership.report(halfway, from: first)
    ownership.showsOriginal = true
    #expect(ownership.state == .shown)
  }

  /// A new load starts under its own header: what the last document's reader said
  /// is stale.
  @Test func `a new load drops the last reader's report`() {
    var ownership = ToolbarTitleOwnership()
    ownership.report(.shown, from: first)
    ownership.beginLoading()
    #expect(ownership.state == .hidden)
  }

  /// The reader gives the title back when it goes away, and it shows.
  @Test func `a reader that goes away gives the title back`() {
    var ownership = ToolbarTitleOwnership()
    ownership.report(.hidden, from: first)
    ownership.release(from: first)
    #expect(ownership.state == .shown)
  }

  /// The reader is made per document, so the last one's teardown can arrive after
  /// the next one has reported; it must not clear what the next one said.
  @Test func `a release by a reader that is not reporting leaves the report alone`() {
    var ownership = ToolbarTitleOwnership()
    ownership.report(halfway, from: second)
    ownership.release(from: first)
    #expect(ownership.state == halfway)
  }
}
