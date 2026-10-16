import Testing

@testable import RFCReaderKit

/// A folding the reader asked the scene for, while the scene has not taken it (#598).
@Suite("Folding echo")
struct FoldingEchoTests {
  private static let closed = Folding(mode: .outline)
  private static let open = Folding(mode: .outline, expanded: ["section-2"])
  private static let other = Folding(mode: .outline, expanded: ["section-3"])

  /// What `echo` admits of each of `foldings`, in turn.
  private static func admitted(_ foldings: [Folding], by echo: inout FoldingEcho) -> [Bool] {
    foldings.map { echo.admits($0) }
  }

  @Test func `with nothing asked, the scene's folding is applied`() {
    var echo = FoldingEcho()

    #expect(Self.admitted([Self.closed], by: &echo) == [true])
  }

  @Test func `the scene's folding from before the change is ignored until it catches up`() {
    var echo = FoldingEcho()
    echo.asked(for: Self.open, from: Self.closed)

    // Caught up, a later return to the old folding is the scene's own change.
    let admitted = Self.admitted([Self.closed, Self.closed, Self.open, Self.closed], by: &echo)
    #expect(admitted == [false, false, true, true])
  }

  @Test func `another folding from the scene is applied, and the change stays pending`() {
    var echo = FoldingEcho()
    echo.asked(for: Self.open, from: Self.closed)

    #expect(Self.admitted([Self.other, Self.closed], by: &echo) == [true, false])
  }

  @Test func `a forgotten change ignores nothing`() {
    var echo = FoldingEcho()
    echo.asked(for: Self.open, from: Self.closed)
    echo.forget()

    #expect(Self.admitted([Self.closed], by: &echo) == [true])
  }
}
