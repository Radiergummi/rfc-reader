/// A refresh that a second call joins rather than runs beside (#595): the index's,
/// the revisions, the working groups and the errata. The index's automatic check is
/// replaceable: a person's refresh replaces it rather than joining it (#983).
///
/// Each refresh is run one of two ways, never both. `start` and `join` run it as a
/// task of its own, which a second call takes, and waits for if it joins.
/// `runUnlessUnderWay` runs it in the caller's task, so that canceling the caller
/// cancels it, and a second call returns at once rather than waiting for it.
@MainActor
public final class SharedRefresh {
  private let name: String
  private var underWay: Task<Void, Never>?
  /// Whether the refresh under way gives way to a start that is not replaceable.
  private var isUnderWayReplaceable = false
  /// Counts the refreshes started, so that one replaced does not, as it ends, end
  /// the one that replaced it.
  private var started = 0
  private var isRunningInCaller = false

  public init(name: String) {
    self.name = name
  }

  public var isUnderWay: Bool { underWay != nil || isRunningInCaller }

  /// The refresh under way, or `operation` started as a new one, which is no longer
  /// under way once it ends.
  ///
  /// A replaceable refresh, such as the index's automatic check, which waits for a
  /// cheap network for as long as there is none, gives way to one that is not, such
  /// as a person's Retry, which takes any network (#983): that start cancels it and
  /// runs once it has ended. Every other start takes the refresh under way.
  @discardableResult
  public func start(
    replaceable: Bool = false, _ operation: @escaping @MainActor () async -> Void
  ) -> Task<Void, Never> {
    var replaced: Task<Void, Never>?
    if let underWay {
      guard isUnderWayReplaceable, !replaceable else { return underWay }
      underWay.cancel()
      replaced = underWay
    }
    started += 1
    let number = started
    let refresh = Task(name: name) {
      await replaced?.value
      await operation()
      if number == started {
        underWay = nil
      }
    }
    underWay = refresh
    isUnderWayReplaceable = replaceable
    return refresh
  }

  /// Waits for the refresh under way, or runs `operation` as a new one and waits
  /// for it, by the same rule as `start`.
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
