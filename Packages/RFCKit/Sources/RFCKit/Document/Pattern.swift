/// A compiled regular expression that can be kept in a `static let` (#146).
///
/// `Regex` is not `Sendable`, so without this wrapper every static pattern would need
/// `nonisolated(unsafe)`, each an unexplained claim that sharing it is safe. It is, for
/// a regex literal, with or without an option such as `ignoresCase()`: a pattern that
/// is only ever matched, never mutated, can be used from any number of threads at once,
/// which is how the parsers use every one of them. This is the one place that says so.
///
/// The claim covers literals, not every `Regex`: one built with a transform closure
/// that captures mutable state is not safe to share, and wrapping it here would silence
/// the compiler rather than make it so. A class-typed output is left for the compiler
/// to catch: the conformance holds only for a `Sendable` output.
///
/// A `RegexComponent`, so a pattern goes wherever a regex literal did:
/// `line.firstMatch(of: Self.footerPattern)` reads the same either way.
struct Pattern<Output>: RegexComponent {
  let regex: Regex<Output>

  init(_ regex: Regex<Output>) {
    self.regex = regex
  }
}

extension Pattern: @unchecked Sendable where Output: Sendable {}
