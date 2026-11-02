import Foundation
import Testing

/// The time limit a test that awaits something carries, so that a hang fails it
/// rather than the job's own timeout (#985): a minute, or the whole minutes CI
/// sets in `RFC_TEST_TIME_LIMIT_MINUTES` for a slow runner.
enum HangGuard {
  static let variable = "RFC_TEST_TIME_LIMIT_MINUTES"

  /// The limit in minutes, or `nil` when the variable is set to something other
  /// than a positive whole number. `HangGuardTests` fails the run on that.
  static func minutes(in environment: [String: String]) -> Int? {
    guard let value = environment[variable] else {
      return 1
    }
    guard let minutes = Int(value), minutes > 0 else {
      return nil
    }
    return minutes
  }
}

extension Trait where Self == TimeLimitTrait {
  static var hangGuard: Self {
    .timeLimit(.minutes(HangGuard.minutes(in: ProcessInfo.processInfo.environment) ?? 1))
  }
}
