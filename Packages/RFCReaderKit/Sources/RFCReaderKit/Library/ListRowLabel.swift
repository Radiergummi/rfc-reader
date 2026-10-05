import Foundation
import RFCKit

extension RFCMetadata {
  /// What a library row is, spoken as one element: which document, what it is
  /// called, and what state it is in, in the order a listener needs it.
  ///
  /// VoiceOver read the row's number, year, title, status and group as separate
  /// stops (#156), so the row hides its children and speaks this instead.
  public func accessibilityLabel(isBookmarked: Bool, locale: Locale = .interface) -> String {
    var parts = [id.displayName, title, currentStatus.displayName]
    if isObsolete {
      parts.append(String(kit: "Obsolete", locale: locale))
    }
    // Prefixed, the index's sentence for no group would be read as "Working group
    // NON WORKING GROUP".
    if let workingGroup = namedWorkingGroup {
      parts.append(String(kit: "Working group \(workingGroup)", locale: locale))
    }
    parts.append(String(date.year))
    if isBookmarked {
      parts.append(String(kit: "Bookmarked", locale: locale))
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

extension LibraryRow {
  /// What the row is, spoken as one element. A series is spoken with the RFCs it
  /// names, and with no status or group: those belong to its members.
  public func accessibilityLabel(isBookmarked: Bool, locale: Locale = .interface) -> String {
    if let rfc { return rfc.accessibilityLabel(isBookmarked: isBookmarked, locale: locale) }
    guard let memberList else { return id.displayName }
    var parts = [id.displayName, title, memberList, String(date.year)]
    if isBookmarked {
      parts.append(String(kit: "Bookmarked", locale: locale))
    }
    return parts.joined(separator: ", ")
  }
}
