/// Writes to a shared object only while the one writing is current (#772): a
/// reader writes the window's reader state only while it is the reader on screen,
/// not while it fades out or lies under the top of the stack.
///
/// The check lives here once, rather than as a guard before each write: a write
/// that forgot its guard put one document's details over another's.
@MainActor @dynamicMemberLookup
public struct ScopedWriter<Root: AnyObject & Sendable> {
  private let root: Root
  private let current: @MainActor @Sendable () -> Bool

  /// A writer to `root` while `current` answers true, asked at each write.
  public init(_ root: Root, while current: @escaping @MainActor @Sendable () -> Bool) {
    self.root = root
    self.current = current
  }

  /// Whether a write now would be made.
  public var isCurrent: Bool { current() }

  /// Reads always; writes only while current. A member that is itself an object is
  /// read, so a write into it (`writer.member.property = …`) is not guarded: make it
  /// in `callAsFunction`.
  public subscript<Value>(dynamicMember keyPath: ReferenceWritableKeyPath<Root, Value>) -> Value {
    get { root[keyPath: keyPath] }
    nonmutating set {
      guard current() else { return }
      root[keyPath: keyPath] = newValue
    }
  }

  /// Runs `write` on the object while current, for what is more than setting a
  /// property: a method that changes it, or several writes that go together.
  public func callAsFunction(_ write: (Root) -> Void) {
    guard current() else { return }
    write(root)
  }
}
