/// Something that happens once, and what waits for it: the index loaded, or arrived
/// or failed to, and the registries readable (#595).
///
/// Waiting on a latch that is open returns at once; opening it resumes everything
/// waiting, and opening it again does nothing. A wait is not canceled with its task:
/// it ends when the latch opens.
@MainActor
public final class Latch {
  public private(set) var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  public init() {}

  public func open() {
    guard !isOpen else { return }
    isOpen = true
    let waiting = waiters
    waiters = []
    for waiter in waiting { waiter.resume() }
  }

  /// Returns once the latch is open.
  public func wait() async {
    guard !isOpen else { return }
    await withCheckedContinuation { waiters.append($0) }
  }
}
