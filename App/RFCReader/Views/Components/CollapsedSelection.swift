import SwiftUI

#if !os(macOS)
  /// A column's `List(selection:)` binding for a collapsed split view, where a row
  /// is a push rather than a selection (#250).
  ///
  /// Popping back writes nil. `NavigationModel`'s filter and selection have no
  /// "nothing" to take it, so a binding straight to them refused it and the row
  /// stayed highlighted for good. This one keeps the pushed row in `pushed`, which
  /// the pop clears, and hands only real choices on to `commit`; the model keeps
  /// its value, and the reader keeps what it loaded.
  @MainActor
  func collapsedSelection<Value>(
    pushed: Binding<Value?>, commit: @escaping @MainActor (Value) -> Void
  ) -> Binding<Value?> {
    Binding(
      get: { pushed.wrappedValue },
      set: { new in
        pushed.wrappedValue = new
        if let new { commit(new) }
      }
    )
  }
#endif
