import Testing

@testable import RFCReaderKit

/// A writer that writes only while its owner is current (#772).
@MainActor @Suite("Scoped writer")
struct ScopedWriterTests {
  @MainActor final class State {
    var title = "first"
    var count = 0
  }

  @MainActor final class Switch {
    var isOn = true
  }

  @Test func `a write while current is made`() {
    let state = State()
    let writer = ScopedWriter(state) { true }

    writer.title = "second"
    writer { $0.count += 1 }

    #expect(state.title == "second")
    #expect(state.count == 1)
  }

  @Test func `a write while not current is dropped`() {
    let state = State()
    let writer = ScopedWriter(state) { false }

    writer.title = "second"
    writer { $0.count += 1 }

    #expect(state.title == "first")
    #expect(state.count == 0)
    #expect(writer.title == "first")
  }

  /// Asked at each write rather than when the writer is made: a writer handed to a
  /// callback outlives the moment it was made in.
  @Test func `currency is asked at each write`() {
    let state = State()
    let shown = Switch()
    let writer = ScopedWriter(state) { shown.isOn }

    writer.title = "second"
    shown.isOn = false
    writer.title = "third"

    #expect(state.title == "second")
    #expect(!writer.isCurrent)
  }
}
