import Testing

@testable import RFCReaderKit

/// How a refresh asked for while one is under way joins it rather than running
/// beside it (#595): the index's, the revisions, the working groups and the
/// errata; and how a person's refresh replaces the index's automatic check (#983).
@MainActor
@Suite("Shared refresh", .timeLimit(.minutes(1)))
struct SharedRefreshTests {
  @Test func `a start while one is under way is the one under way`() async {
    let refresh = SharedRefresh(name: "Test")
    let log = Log()
    let started = Latch()
    let gate = Latch()
    let first = refresh.start {
      log.events.append("first")
      started.open()
      await gate.wait()
    }
    await started.wait()
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

  /// The index: a person's Retry or pull to refresh, on any network, does not wait
  /// for the automatic check, which may wait for a cheap network for as long as
  /// there is none (#983). It cancels it and runs once it has ended.
  @Test func `a start replaces a replaceable one under way`() async {
    let refresh = SharedRefresh(name: "Test")
    let log = Log()
    let started = Latch()
    let gate = Latch()
    let secondGate = Latch()
    let first = refresh.start(replaceable: true) {
      started.open()
      await gate.wait()
      log.events.append(Task.isCancelled ? "first canceled" : "first ended")
    }
    await started.wait()
    let second = refresh.start {
      log.events.append("second ran")
      await secondGate.wait()
    }
    #expect(first != second)
    gate.open()
    await first.value
    // The replaced one ending leaves the one that replaced it under way.
    #expect(refresh.isUnderWay)
    #expect(refresh.start(replaceable: true) {} == second)
    secondGate.open()
    await second.value
    #expect(log.events == ["first canceled", "second ran"])
    #expect(!refresh.isUnderWay)
  }

  /// The index: pull to refresh and the first launch wait for the index fetched
  /// now, not for the automatic check (#984).
  @Test func `joining replaces a replaceable one under way`() async {
    let refresh = SharedRefresh(name: "Test")
    let log = Log()
    let started = Latch()
    let gate = Latch()
    let first = refresh.start(replaceable: true) {
      started.open()
      await gate.wait()
      log.events.append(Task.isCancelled ? "first canceled" : "first ended")
    }
    await started.wait()
    // Immediate, so that it has replaced the first before the gate opens.
    let joiner = Task.immediate {
      await refresh.join { log.events.append("joined ran") }
      log.events.append("join returned")
    }
    gate.open()
    await first.value
    await joiner.value
    #expect(log.events == ["first canceled", "joined ran", "join returned"])
  }

  /// The index: the automatic check takes a person's refresh under way, which
  /// takes any network.
  @Test func `a replaceable start is the one under way`() async {
    let refresh = SharedRefresh(name: "Test")
    let log = Log()
    let started = Latch()
    let gate = Latch()
    let first = refresh.start {
      started.open()
      await gate.wait()
      log.events.append(Task.isCancelled ? "first canceled" : "first ended")
    }
    await started.wait()
    let second = refresh.start(replaceable: true) { log.events.append("second ran") }
    #expect(first == second)
    gate.open()
    await first.value
    #expect(log.events == ["first ended"])
  }

  /// Two automatic checks of the index are one.
  @Test func `a replaceable start joins a replaceable one under way`() async {
    let refresh = SharedRefresh(name: "Test")
    let log = Log()
    let started = Latch()
    let gate = Latch()
    let first = refresh.start(replaceable: true) {
      started.open()
      await gate.wait()
      log.events.append(Task.isCancelled ? "first canceled" : "first ended")
    }
    await started.wait()
    let second = refresh.start(replaceable: true) { log.events.append("second ran") }
    #expect(first == second)
    gate.open()
    await first.value
    #expect(log.events == ["first ended"])
  }

  /// The revisions: a background refresh that asks returns only once the file is
  /// in (#191).
  @Test func `joining waits for the one under way to end`() async {
    let refresh = SharedRefresh(name: "Test")
    let log = Log()
    let started = Latch()
    let gate = Latch()
    let first = refresh.start {
      started.open()
      await gate.wait()
      log.events.append("first ended")
    }
    await started.wait()
    // Immediate, so that it has joined before the gate opens.
    let joiner = Task.immediate {
      await refresh.join { log.events.append("joined ran") }
      log.events.append("join returned")
    }
    gate.open()
    await first.value
    await joiner.value
    #expect(log.events == ["first ended", "join returned"])
  }

  /// The working groups and the errata: a second call, at launch or on an
  /// activation, returns at once rather than waiting for the first.
  @Test func `running unless one is under way returns at once while one is`() async {
    let refresh = SharedRefresh(name: "Test")
    let log = Log()
    let gate = Latch()
    // Immediate, so that it is under way before the second call.
    let first = Task.immediate {
      await refresh.runUnlessUnderWay {
        await gate.wait()
        log.events.append("first ended")
      }
    }
    #expect(refresh.isUnderWay)
    await refresh.runUnlessUnderWay { log.events.append("second ran") }
    log.events.append("second returned")
    gate.open()
    await first.value
    #expect(log.events == ["second returned", "first ended"])
    #expect(!refresh.isUnderWay)
  }

  /// In the caller's task, so that canceling the caller cancels it.
  @Test func `running unless one is under way runs in the caller's task`() async {
    let refresh = SharedRefresh(name: "Test")
    let log = Log()
    let caller = Task {
      await refresh.runUnlessUnderWay {
        withUnsafeCurrentTask {
          log.events.append($0?.isCancelled == true ? "canceled" : "running")
        }
      }
    }
    caller.cancel()
    await caller.value
    #expect(log.events == ["canceled"])
  }
}
