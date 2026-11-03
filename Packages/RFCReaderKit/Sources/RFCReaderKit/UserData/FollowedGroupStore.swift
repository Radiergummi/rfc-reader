import Foundation
import SwiftData

/// The one place a `FollowedGroup` is read or written (#731), on `OfflineMarkStore`'s
/// terms: every failure is thrown, and the App decides what to do with it.
///
/// Nobody displays the state by asking here: `UserDataMirror` reads
/// `followedGroups(in:)` after every save of a followed group.
@MainActor
public enum FollowedGroupStore {
  /// The acronym of every followed group, in lower case. Only the acronyms are
  /// fetched.
  public static func followedGroups(in context: ModelContext) throws -> Set<String> {
    var descriptor = FetchDescriptor<FollowedGroup>()
    descriptor.propertiesToFetch = [\.acronym]
    return Set(try context.fetch(descriptor).map(\.acronym))
  }

  /// Follows the group `acronym` names, in any case, or stops following it, and
  /// saves. Following a group already followed adds nothing.
  public static func setFollowed(_ acronym: String, _ isFollowed: Bool, in context: ModelContext)
    throws
  {
    let key = acronym.lowercased()
    let existing = try context.fetch(
      FetchDescriptor<FollowedGroup>(predicate: #Predicate { $0.acronym == key }))
    if isFollowed {
      guard existing.isEmpty else { return }
      context.insert(FollowedGroup(acronym: key))
    } else {
      guard !existing.isEmpty else { return }
      // Every row naming the group, since nothing stops there being two.
      existing.forEach(context.delete)
    }
    try context.save()
  }
}
