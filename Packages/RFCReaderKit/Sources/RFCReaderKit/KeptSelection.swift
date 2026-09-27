/// A list's selection that can be cleared without the choice behind it being lost.
///
/// A collapsed split view writes nil to a column's selection when it goes back to
/// that column. The sidebar's filter must take that nil, or its row stays
/// highlighted (#250), but the document list still lists the filter until another
/// one is chosen, so it does not change under the animation back (#261).
public struct KeptSelection<Value: Equatable & Sendable>: Sendable {
  /// The last value chosen, cleared or not.
  public private(set) var value: Value
  private var isCleared = false

  public init(_ value: Value) {
    self.value = value
  }

  /// What the list shows as selected: `value`, or nil once cleared.
  public var selection: Value? {
    get { isCleared ? nil : value }
    set {
      if let newValue { value = newValue }
      isCleared = newValue == nil
    }
  }

  /// Whether this selection entered a value that `previous` did not show as
  /// selected. Not a change of `value`: choosing the kept value again after a
  /// clear enters it too, and that is how a collapsed split view comes back to it.
  public func enters(since previous: Self) -> Bool {
    selection != nil && selection != previous.selection
  }
}
