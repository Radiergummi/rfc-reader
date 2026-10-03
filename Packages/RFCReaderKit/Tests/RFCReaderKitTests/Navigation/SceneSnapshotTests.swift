import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// What a tab keeps across launches (#155): its history, its filter and its
/// inspector tab, written as the tab changes and read back when it is made again.
@Suite
struct SceneSnapshotTests {
  private func place(_ number: Int, _ section: String? = nil) -> HistoryEntry {
    HistoryEntry(id: .rfc(number), section: section)
  }

  /// A history that went to `numbers` in turn, then stepped back `back` times.
  private func history(through numbers: some Sequence<Int>, back: Int = 0) -> NavigationHistory {
    var history = NavigationHistory()
    for number in numbers { history.go(to: place(number)) }
    for _ in 0..<back { history.goBack() }
    return history
  }

  @Test func `a snapshot reads back as it was written`() throws {
    var navigation = history(through: [9110, 9111, 9112], back: 1)
    navigation.hide()
    let snapshot = SceneSnapshot(
      history: navigation.snapshot(), filter: .collection(UUID()), inspectorTab: "references")
    let data = try #require(snapshot.encoded())
    #expect(SceneSnapshot.decoded(from: data) == snapshot)
  }

  @Test func `a restored history walks back and forward through the same places`() {
    var restored = NavigationHistory(history(through: [9110, 9111, 9112], back: 1).snapshot())
    #expect(restored.shown == place(9111))
    #expect(restored.goBack() == place(9110))
    #expect(restored.goForward() == place(9111))
    #expect(restored.goForward() == place(9112))
    #expect(restored.goForward() == nil)
  }

  /// Put away on an iPhone or deselected on a Mac, the document stays hidden, and
  /// its row still reopens it where it was.
  @Test func `a hidden document is restored hidden`() {
    var navigation = history(through: [9110])
    navigation.hide()
    var restored = NavigationHistory(navigation.snapshot())
    #expect(restored.shown == nil)
    #expect(restored.current == place(9110))
    #expect(restored.go(to: place(9110)) == nil)
    #expect(restored.shown == place(9110))
  }

  /// Restoring is not arriving: Back straight after a launch leaves the document,
  /// rather than offering to undo a jump made in another session.
  @Test func `a restored history offers no way back from a jump`() {
    var navigation = history(through: [9110])
    navigation.go(to: place(9110, "section-4"), leaving: "section-2")
    #expect(navigation.returnOffer != nil)
    #expect(NavigationHistory(navigation.snapshot()).returnOffer == nil)
  }

  @Test func `a long history keeps the fifty places nearest the current one`() {
    let snapshot = history(through: 1...80).snapshot()
    var restored = NavigationHistory(snapshot)
    var visited = [restored.shown]
    while let place = restored.goBack() { visited.append(place) }
    #expect(visited == (31...80).reversed().map { place($0) })
  }

  @Test func `a history long on both sides keeps places on both sides of the current one`() {
    var restored = NavigationHistory(history(through: 1...100, back: 50).snapshot())
    #expect(restored.shown == place(50))
    while restored.goBack() != nil {}
    var kept = [restored.shown]
    while let place = restored.goForward() { kept.append(place) }
    #expect(kept == (25...74).map { place($0) })
  }

  @Test func `a history that fits is kept whole`() {
    let navigation = history(through: 1...10, back: 4)
    var restored = NavigationHistory(navigation.snapshot())
    var backward = 0
    while restored.goBack() != nil { backward += 1 }
    #expect(backward == 5)
    var forward = 0
    while restored.goForward() != nil { forward += 1 }
    #expect(forward == 9)
  }

  /// An app that changes what it keeps starts the tab afresh rather than failing
  /// to make it.
  @Test func `a snapshot of another version reads as none`() throws {
    let snapshot = SceneSnapshot(history: NavigationHistory().snapshot(), filter: .all)
    let data = try #require(snapshot.encoded())
    var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["version"] = SceneSnapshot.version + 1
    let other = try JSONSerialization.data(withJSONObject: object)
    #expect(SceneSnapshot.decoded(from: other) == nil)
  }

  @Test func `data that is no snapshot reads as none`() {
    #expect(SceneSnapshot.decoded(from: Data("not a snapshot".utf8)) == nil)
    #expect(SceneSnapshot.decoded(from: Data(#"{"version": 1}"#.utf8)) == nil)
  }

  @Test func `every filter survives the trip`() throws {
    let filters: [LibraryFilter] = [
      .all, .recent, .bookmarks, .downloaded, .standards, .bestCurrentPractice,
      .stream(.ietf), .workingGroup("httpbis"), .series(DocumentID(series: .bcp, number: 14)),
      .collection(UUID()),
    ]
    for filter in filters {
      let snapshot = SceneSnapshot(history: NavigationHistory().snapshot(), filter: filter)
      let data = try #require(snapshot.encoded())
      #expect(SceneSnapshot.decoded(from: data)?.filter == filter)
    }
  }
}
