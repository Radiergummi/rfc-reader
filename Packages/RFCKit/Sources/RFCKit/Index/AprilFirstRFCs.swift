/// The RFCs published on 1 April as jokes, which a reader can hide from the
/// library's lists, its search and Just Published (#713).
///
/// Curated by hand, by number only, and never guessed from the date: some real RFCs
/// were published on 1 April too. Each is one the index dates 1 April and lists as
/// Informational or Experimental, which `AprilFirstRFCsTests` checks against it.
public enum AprilFirstRFCs {
  public static let numbers: Set<Int> = [
    1149, 1216, 1217, 1313, 1437, 1438, 1605, 1606, 1607, 1776, 1924, 1925, 1926, 1927,
    2100, 2321, 2322, 2323, 2324, 2325, 2549, 2550, 2551, 2795, 3091, 3092, 3093, 3251,
    3252, 3514, 4041, 4042, 4824, 5241, 5242, 5513, 5514, 5841, 6919, 6921, 7168, 7169,
    7511, 7514, 8135, 8136, 8140, 8367, 8369, 8565, 8567, 8771, 8774, 8962, 9401, 9402,
    9405, 9564, 9759, 9948, 9949,
  ]

  /// Whether `id` is one of them: an RFC, never a series.
  public static func contains(_ id: DocumentID) -> Bool {
    id.series == .rfc && numbers.contains(id.number)
  }
}
