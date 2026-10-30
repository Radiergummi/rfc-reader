import Testing

/// The time limit that turns a hang into a failure (#985): a minute, unless the
/// environment gives one the run's own queueing cannot reach.
@Suite("Hang guard")
struct HangGuardTests {
  @Test func `without a setting the limit is a minute`() {
    #expect(HangGuard.minutes(in: [:]) == 1)
  }

  @Test func `a setting in whole minutes replaces it`() {
    #expect(HangGuard.minutes(in: [HangGuard.variable: "10"]) == 10)
  }

  @Test(arguments: ["", "0", "-1", "ten", "1.5"])
  func `a setting that is not a positive whole number is ignored`(value: String) {
    #expect(HangGuard.minutes(in: [HangGuard.variable: value]) == 1)
  }
}
