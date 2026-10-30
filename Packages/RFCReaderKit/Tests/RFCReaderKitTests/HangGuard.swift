import Foundation
import Testing

/// The time limit a test that awaits something carries, so that a hang fails it
/// rather than the job's own timeout (#985).
///
/// A test's time counts from when it is started, and every test is started at
/// once: a main-actor test waits behind every other main-actor test, the
/// builders' and TextKit's included, wherever it awaits. On a Mac the whole run
/// takes seconds, and a minute is a hang. On the iOS Simulator of a CI runner it
/// can take minutes, so CI gives a longer limit in `RFC_TEST_TIME_LIMIT_MINUTES`
/// (for the Simulator, `TEST_RUNNER_RFC_TEST_TIME_LIMIT_MINUTES`, which
/// xcodebuild hands to the test process without its prefix).
enum HangGuard {
  static let variable = "RFC_TEST_TIME_LIMIT_MINUTES"

  static func minutes(in environment: [String: String]) -> Int {
    guard let value = environment[variable], let minutes = Int(value), minutes > 0 else {
      return 1
    }
    return minutes
  }
}

extension Trait where Self == TimeLimitTrait {
  static var hangGuard: Self {
    .timeLimit(.minutes(HangGuard.minutes(in: ProcessInfo.processInfo.environment)))
  }
}
