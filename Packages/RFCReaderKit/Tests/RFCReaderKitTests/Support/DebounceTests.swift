import Testing

@testable import RFCReaderKit

/// A debounced search runs once per change of the query, and the next change
/// cancels it: only a pause that outlasts the delay reaches the search (#604).
@Suite("Debounce")
struct DebounceTests {
  @Test func `a pause that outlasts the delay goes on`() async {
    #expect(await Debounce.outlasted(.milliseconds(1)))
  }

  @Test func `no delay goes on at once`() async {
    #expect(await Debounce.outlasted(.zero))
  }

  @Test func `a change during the pause stops it`() async {
    let pause = Task { await Debounce.outlasted(.seconds(60)) }
    pause.cancel()
    #expect(await pause.value == false)
  }

  @Test func `a change before the pause stops it even without a delay`() async {
    let pause = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return await Debounce.outlasted(.zero)
    }
    #expect(await pause.value == false)
  }
}
