import Foundation

/// A compiled regular expression that can be kept in a `static let` (#146).
///
/// `Regex` is not `Sendable`, so a static pattern needed `nonisolated(unsafe)` at every
/// declaration, twenty-eight times, each an unexplained claim that sharing it was
/// safe. It is: a pattern that is only ever matched, never mutated, can be used from
/// any number of threads at once, which is how the parsers use every one of them.
/// This is the one place that says so.
///
/// A `RegexComponent`, so a pattern goes wherever a regex literal did:
/// `line.firstMatch(of: Self.footerPattern)` reads the same either way.
struct Pattern<Output>: RegexComponent, @unchecked Sendable {
  let regex: Regex<Output>

  init(_ regex: Regex<Output>) {
    self.regex = regex
  }
}
