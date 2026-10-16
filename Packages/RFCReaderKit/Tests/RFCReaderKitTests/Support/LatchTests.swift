import Testing

@testable import RFCReaderKit

/// What waits for something to have happened once: the index loaded or settled,
/// the registries readable (#595).
@MainActor
@Suite("Latch")
struct LatchTests {
  @Test func `a latch starts closed`() {
    #expect(!Latch().isOpen)
  }

  @Test func `waiting on an open latch returns at once`() async {
    let latch = Latch()
    latch.open()
    await latch.wait()
    #expect(latch.isOpen)
  }

  @Test(.timeLimit(.minutes(1)))
  func `opening resumes everything that waited`() async {
    let latch = Latch()
    let log = Log()
    // Immediate, so that each is waiting before the latch opens.
    let first = Task.immediate {
      await latch.wait()
      log.events.append("first")
    }
    let second = Task.immediate {
      await latch.wait()
      log.events.append("second")
    }
    #expect(log.events.isEmpty)
    latch.open()
    await first.value
    await second.value
    #expect(Set(log.events) == ["first", "second"])
  }

  @Test func `opening twice is opening once`() async {
    let latch = Latch()
    latch.open()
    latch.open()
    await latch.wait()
    #expect(latch.isOpen)
  }
}

@MainActor
final class Log {
  var events: [String] = []
}
