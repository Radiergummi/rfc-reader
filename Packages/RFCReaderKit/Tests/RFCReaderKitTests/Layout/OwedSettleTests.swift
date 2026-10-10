import Testing

@testable import RFCReaderKit

/// When the end of a live resize settles the reader's place (#542).
@Suite("Owed settle")
struct OwedSettleTests {
  /// A divider dragged, or the inspector opened, with no rebuild in it.
  @Test func `a resize with no rebuild in it ends with a pin`() {
    #expect(OwedSettle().atResizeEnd == .pin)
  }

  /// The window resized while the inspector's closing animation runs: the rebuild for
  /// the new column lands inside the resize, and its settle comes at the end.
  @Test func `a rebuild pinned during the resize is settled at its end`() {
    var owed = OwedSettle()
    owed.pinnedRebuild()
    #expect(owed.atResizeEnd == .settle)
  }

  /// The rebuild landed after the resize ended and settled itself, or the end of the
  /// resize settled: the next resize owes nothing.
  @Test func `a settle made by anyone clears what is owed`() {
    var owed = OwedSettle()
    owed.pinnedRebuild()
    owed.settled()
    #expect(owed.atResizeEnd == .pin)
  }

  /// The column went back to the one on screen during the resize, so no rebuild
  /// follows: what an earlier rebuild in it owes stays owed.
  @Test func `nothing but a settle clears what is owed`() {
    var owed = OwedSettle()
    owed.pinnedRebuild()
    owed.pinnedRebuild()
    #expect(owed.isOwed)
  }
}
