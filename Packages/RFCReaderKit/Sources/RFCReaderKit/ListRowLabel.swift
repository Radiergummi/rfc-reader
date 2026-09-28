import Foundation
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
    // Prefixed, the index's sentence for no group would be read as "Working group
    // NON WORKING GROUP".
    if let workingGroup = namedWorkingGroup {
      parts.append("Working group \(workingGroup)")
    }
    parts.append(String(date.year))
    if isBookmarked {
      parts.append("Bookmarked")
    }
    return parts.joined(separator: ", ")
  }

  /// The working group, or nil for a document from none: the index fills the field
  /// for those with the sentence "NON WORKING GROUP" rather than leaving it empty.
  var namedWorkingGroup: String? {
    guard let workingGroup, workingGroup.caseInsensitiveCompare("NON WORKING GROUP") != .orderedSame
    else {
      return nil
    }
    return workingGroup
  }
}
