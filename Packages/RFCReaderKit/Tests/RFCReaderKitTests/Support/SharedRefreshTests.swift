import Testing

@testable import RFCReaderKit

/// How a refresh asked for while one is under way joins it rather than running
/// beside it (#595): the index's check and Retry, the revisions, the working
/// groups and the errata.
@MainActor
@Suite("Shared refresh", .timeLimit(.minutes(1)))
struct SharedRefreshTests {
  @Test func `a start while one is under way is the one under way`() async {
    let refresh = SharedRefresh(name: "Test")
    let log = Log()
    let gate = Latch()
    let first = refresh.start {
      log.events.append("first")
      await gate.wait()
    }
    let second = refresh.start { log.events.append("second") }
    #expect(first == second)
    #expect(refresh.isUnderWay)
    gate.open()
    await first.value
    #expect(log.events == ["first"])
    #expect(!refresh.isUnderWay)
  }

  @Test func `a start after the last one ended runs again`() async {
    let refresh = SharedRefresh(name: "Test")
    let log = Log()
    await refresh.start { log.events.append("first") }.value
    await refresh.start { log.events.append("second") }.value
    #expect(log.events == ["first", "second"])
  }

  /// The revisions: a background refresh that asks returns only once the file is
  /// in (#191).
  @Test func `joining waits for the one under way to end`() async {
    let refresh = SharedRefresh(name: "Test")
    let log = Log()
    let gate = Latch()
    let first = refresh.start {
      await gate.wait()
      log.events.append("first ended")
    }
    let joiner = Task.immediate {
      await refresh.join { log.events.append("joined ran") }
      log.events.append("join returned")
    }
    gate.open()
    await first.value
    await joiner.value
    #expect(log.events == ["first ended", "join returned"])
  }

  /// The working groups and the errata: a second call returns at once, so
  /// `refreshForBookmarks` does not wait for them.
  @Test func `running unless one is under way returns at once while one is`() async {
    let refresh = SharedRefresh(name: "Test")
    let log = Log()
    let gate = Latch()
    let first = refresh.start {
      await gate.wait()
      log.events.append("first ended")
    }
    await refresh.runUnlessUnderWay { log.events.append("second ran") }
    log.events.append("second returned")
    gate.open()
    await first.value
    #expect(log.events == ["second returned", "first ended"])
  }

  @Test func `running unless one is under way runs when none is, and waits for it`() async {
    let refresh = SharedRefresh(name: "Test")
    let log = Log()
    await refresh.runUnlessUnderWay {
      await Task.yield()
      log.events.append("ran")
    }
    log.events.append("returned")
    #expect(log.events == ["ran", "returned"])
    #expect(!refresh.isUnderWay)
  }
}
