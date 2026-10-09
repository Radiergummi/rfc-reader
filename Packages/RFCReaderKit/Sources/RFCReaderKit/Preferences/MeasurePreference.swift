/// How wide the reader sets its text.
///
/// A setting, stored by its raw value — so the case names are what user defaults
/// hold, and renaming one resets everyone's choice. An enum rather than a flag, so
/// a third choice — an explicit measure — does not change every signature again.
public enum MeasurePreference: String, CaseIterable, Sendable {
  /// Capped at `ReaderLayout.idealMeasure`, the gutters growing beyond it.
  case recommended
  /// Out to the margins however wide the reader is, the way `less` does.
  case fullWidth
}
