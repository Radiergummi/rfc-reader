/// A refresh that a second call joins rather than runs beside (#595): the index's
/// daily check and Retry, the revisions, the working groups and the errata.
///
/// Each refresh is run one of two ways, never both. `start` and `join` run it as a
/// task of its own, which a second call takes, and waits for if it joins.
/// `runUnlessUnderWay` runs it in the caller's task, so that canceling the caller
/// cancels it, and a second call returns at once rather than waiting for it.
@MainActor
public final class SharedRefresh {
  private let name: String
  private var underWay: Task<Void, Never>?
  private var isRunningInCaller = false

  public init(name: String) {
    self.name = name
  }

  public var isUnderWay: Bool { underWay != nil || isRunningInCaller }

  /// The refresh under way, or `operation` started as a new one, which is no longer
  /// under way once it ends.
  @discardableResult
  public func start(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
    if let underWay { return underWay }
    let refresh = Task(name: name) {
      await operation()
      underWay = nil
    }
    underWay = refresh
    return refresh
  }

  /// Waits for the refresh under way, or runs `operation` as a new one and waits
  /// for it.
  public func join(_ operation: @escaping @MainActor () async -> Void) async {
    await start(operation).value
  }

  /// Returns at once while a refresh is under way; otherwise runs `operation` in the
  /// caller's task.
  public func runUnlessUnderWay(_ operation: @MainActor () async -> Void) async {
    guard !isUnderWay else { return }
    isRunningInCaller = true
    defer { isRunningInCaller = false }
    await operation()
  }
}
