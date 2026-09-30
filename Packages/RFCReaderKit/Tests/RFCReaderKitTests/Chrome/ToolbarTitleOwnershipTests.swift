import CoreGraphics
import Testing

@testable import RFCReaderKit

/// One owner for how far the document's title has come into the toolbar (#281): a
/// reader with a header on screen says where it is; without one, the title shows
/// where the document has no header, and stays out while one is on its way.
@Suite("Toolbar title ownership")
struct ToolbarTitleOwnershipTests {
  private final class Reader {}
  private let readers = (Reader(), Reader())
  private var first: ObjectIdentifier { ObjectIdentifier(readers.0) }
  private var second: ObjectIdentifier { ObjectIdentifier(readers.1) }
  private let halfway = ToolbarTitleState(reveal: 0.5, runningHeading: .steady(nil))

  /// Nothing to name: the toolbar shows no title over an empty reader.
  @Test func `with no document the title is hidden`() {
    #expect(ToolbarTitleOwnership().state == .hidden)
  }

  /// Loading counts as a header on its way, so the title stays out rather than
  /// flashing in before the new document's header appears; and it stays out after
  /// the load, until the reader reports.
  @Test func `a document whose reader has not reported hides the title`() {
    var ownership = ToolbarTitleOwnership()
    ownership.beginLoading()
    #expect(ownership.state == .hidden)
  }

  @Test func `the reader's report is the title's state`() {
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
    ownership.beginLoading()
    ownership.report(.shown, from: first)
    ownership.beginLoading()
    #expect(ownership.state == .hidden)
  }

  /// Deselected: the title goes with the document, whatever mode it was shown in.
  @Test func `closing the document hides the title`() {
    var ownership = ToolbarTitleOwnership()
    ownership.beginLoading()
    ownership.failLoading()
    ownership.close()
    #expect(ownership.state == .hidden)
  }

  /// A reader that goes away takes what it said with it. The document is still open,
  /// under a header the next reader will report on, so the title stays out.
  @Test func `a reader that goes away takes its report with it`() {
    var ownership = ToolbarTitleOwnership()
    ownership.beginLoading()
    ownership.report(.shown, from: first)
    ownership.release(from: first)
    #expect(ownership.state == .hidden)
  }

  /// The reader is made per document, so the last one's teardown can arrive after
  /// the next one has reported; it must not clear what the next one said.
  @Test func `a release by a reader that is not reporting leaves the report alone`() {
    var ownership = ToolbarTitleOwnership()
    ownership.beginLoading()
    ownership.report(halfway, from: second)
    ownership.release(from: first)
    #expect(ownership.state == halfway)
  }
}
