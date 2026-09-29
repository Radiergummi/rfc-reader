/// A compiled regular expression that can be kept in a `static let` (#146).
///
/// `Regex` is not `Sendable`, so without this wrapper every static pattern would need
/// `nonisolated(unsafe)`, each an unexplained claim that sharing it is safe. It is, for
/// a regex literal: a pattern that is only ever matched, never mutated, can be used from
/// any number of threads at once, which is how the parsers use every one of them. This
/// is the one place that says so.
///
/// The claim covers literals, not every `Regex`: one built with a transform closure
/// that captures mutable state, or with a class-typed output, is not safe to share, and
/// wrapping it here would silence the compiler rather than make it so.
///
/// A `RegexComponent`, so a pattern goes wherever a regex literal did:
/// `line.firstMatch(of: Self.footerPattern)` reads the same either way.
struct Pattern<Output>: RegexComponent, @unchecked Sendable {
  let regex: Regex<Output>

  init(_ regex: Regex<Output>) {
    self.regex = regex
  }
}
