import Foundation

/// What following a working group (#731) means to the chrome: which groups the
/// sidebar lists, and what the command that follows one says.
public enum WorkingGroupFollowing {
  /// The Working Groups section of the sidebar: the followed groups first, by name,
  /// then the busiest groups (`PreparedIndex.topWorkingGroups`) not already listed.
  /// Both in lower case, as the index spells an acronym.
  public static func sidebarGroups(followed: Set<String>, top: [String]) -> [String] {
    followed.sorted() + top.filter { !followed.contains($0) }
  }

  /// Whether `acronym` names a group: the index fills the field of an RFC from no
  /// group with "NON WORKING GROUP", which lists RFCs but is not one to follow.
  public static func canFollow(_ acronym: String) -> Bool {
    !acronym.isEmpty && acronym.caseInsensitiveCompare("NON WORKING GROUP") != .orderedSame
  }

  /// "Follow Working Group", or "Unfollow Working Group" for one already followed.
  public static func command(isFollowed: Bool, locale: Locale = .interface) -> String {
    isFollowed
      ? String(kit: "Unfollow Working Group", locale: locale)
      : String(kit: "Follow Working Group", locale: locale)
  }

  /// The SF Symbol beside `command`.
  public static func symbol(isFollowed: Bool) -> String {
    isFollowed ? "bell.slash" : "bell"
  }
}
