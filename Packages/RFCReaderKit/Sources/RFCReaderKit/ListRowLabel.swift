import RFCKit

extension RFCMetadata {
  /// What a library row is, spoken as one element: which document, what it is
  /// called, and what state it is in, in the order a listener needs it.
  ///
  /// VoiceOver read the row's number, year, title, status and group as separate
  /// stops (#156), so the row hides its children and speaks this instead.
  public func accessibilityLabel(isBookmarked: Bool) -> String {
    var parts = [id.displayName, title, currentStatus.displayName]
    if isObsolete {
      parts.append("Obsolete")
    }
    // The index fills the field for documents from no group with this sentence
    // rather than leaving it empty; prefixed, it would be read as "Working group
    // NON WORKING GROUP".
    if let workingGroup, workingGroup.caseInsensitiveCompare("NON WORKING GROUP") != .orderedSame {
      parts.append("Working group \(workingGroup)")
    }
    parts.append(String(date.year))
    if isBookmarked {
      parts.append("Bookmarked")
    }
    return parts.joined(separator: ", ")
  }
}
