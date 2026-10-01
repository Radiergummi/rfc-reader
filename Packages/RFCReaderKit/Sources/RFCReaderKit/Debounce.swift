/// The wait of a debounced task: one runs per change, and the next change cancels it,
/// so only a pause long enough to outlast the delay reaches the work behind it. The
/// Go to RFC palette and the document list's search each wait this way, with delays
/// of their own (#604).
public enum Debounce {
  /// Waits `delay`, and answers whether the task is still wanted at its end: false
  /// when it was canceled before or during the wait. A zero delay does not suspend.
  public static func outlasted(_ delay: Duration) async -> Bool {
    if delay > .zero {
      do {
        try await Task.sleep(for: delay)
      } catch {
        return false
      }
    }
    return !Task.isCancelled
  }
}
