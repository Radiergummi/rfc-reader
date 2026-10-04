import RFCKit

/// Which files of `convert --in` a run converts, and in what order.
public enum ConversionPlan {
  /// Numbers `--only` asked for that have no text in `--in`.
  public struct MissingText: Error, CustomStringConvertible {
    public var numbers: [Int]

    public var description: String {
      "no text in --in for \(numbers.map { "rfc\($0)" }.joined(separator: ", "))"
    }
  }

  /// The `.txt` files among `names`, in document order. With `only`, just those RFC
  /// numbers, and every one of them must be there: a number asked for by name is
  /// expected to be converted, so one with no text fails the run rather than being
  /// skipped.
  public static func files(in names: [String], only: [Int] = []) throws -> [String] {
    var files = names.filter { $0.hasSuffix(".txt") }
      .sorted { (rfcNumber(of: $0) ?? 0) < (rfcNumber(of: $1) ?? 0) }
    guard !only.isEmpty else { return files }
    let wanted = Set(only)
    files = files.filter { rfcNumber(of: $0).map(wanted.contains) ?? false }
    let missing = wanted.subtracting(files.compactMap(rfcNumber(of:))).sorted()
    guard missing.isEmpty else { throw MissingText(numbers: missing) }
    return files
  }

  /// The RFC number of a corpus file name: 2119 for `rfc2119.txt` or `rfc2119`. The
  /// name must be the stem `DocumentID.fileStem` writes, and of an RFC: `bcp14.txt`
  /// names no RFC number, where its number alone would take RFC 14's index entry.
  public static func rfcNumber(of fileName: String) -> Int? {
    guard let id = DocumentID(fileStem: String(fileName.split(separator: ".").first ?? "")),
      id.series == .rfc
    else { return nil }
    return id.number
  }
}
