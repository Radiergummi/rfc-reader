/// A convert run's schema results against the report it replaced.
///
/// The documents that stopped validating are the regressions, listed by name: a count
/// that netted them against the documents that started would hide them. Only the
/// documents this run converted are compared, so a run over part of the corpus says
/// nothing about the rest.
public struct SchemaComparison: Equatable, Sendable {
  /// The documents that validated in the previous report and do not now, in report
  /// order. A document skipped now is not among them: it has no XML to validate, by a
  /// decision of its own (`Manifest.Skip`). Nor is one whose patch failed, which has no
  /// XML either and fails the run on its own (`DocumentReport.failure`).
  public var stoppedValidating: [String]
  /// How many documents validate now that did not in the previous report, or were not
  /// in it.
  public var startedValidating: Int

  /// Whether any document stopped validating, which fails the run.
  public var isRegression: Bool { !stoppedValidating.isEmpty }

  /// Compares `reports` with the documents that validated in the previous report
  /// (`DocumentReport.validDocuments(inReport:)`).
  public init(reports: [DocumentReport], previouslyValid: Set<String>) {
    stoppedValidating =
      reports
      .filter {
        previouslyValid.contains($0.id) && $0.schema != [] && $0.skipped == nil
          && $0.failure == nil
      }
      .map(\.id)
    startedValidating =
      reports
      .filter { $0.schema == [] && !previouslyValid.contains($0.id) }
      .count
  }
}
