import Foundation
import RFCKit
import SwiftData
import Testing

@testable import RFCReaderKit

/// Following a working group (#731): the store, the mirror that reads it, and what
/// the sidebar and the menus make of it.
@Suite("Followed working groups")
@MainActor
struct FollowedGroupTests {
  /// Held by each test: a context does not keep its container alive, and one freed
  /// under it traps.
  private func makeContainer() throws -> ModelContainer {
    try UserData.container(configurations: ModelConfiguration(isStoredInMemoryOnly: true))
  }

  // MARK: - Store

  @Test func `following a group adds it and unfollowing removes it`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    try FollowedGroupStore.setFollowed("httpbis", true, in: context)
    #expect(try FollowedGroupStore.followedGroups(in: context) == ["httpbis"])

    try FollowedGroupStore.setFollowed("httpbis", false, in: context)
    #expect(try FollowedGroupStore.followedGroups(in: context).isEmpty)
  }

  @Test func `following a followed group again adds no second row`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    try FollowedGroupStore.setFollowed("httpbis", true, in: context)
    try FollowedGroupStore.setFollowed("httpbis", true, in: context)
    #expect(try context.fetchCount(FetchDescriptor<FollowedGroup>()) == 1)
  }

  /// The index spells an acronym in lower case, and a card or a script may not.
  @Test func `a group is followed by its acronym in lower case`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    try FollowedGroupStore.setFollowed("HTTPBIS", true, in: context)
    try FollowedGroupStore.setFollowed("httpbis", true, in: context)
    #expect(try FollowedGroupStore.followedGroups(in: context) == ["httpbis"])
    #expect(try context.fetchCount(FetchDescriptor<FollowedGroup>()) == 1)
  }

  /// CloudKit can deliver two rows for one group.
  @Test func `unfollowing removes every row naming the group`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    context.insert(FollowedGroup(acronym: "httpbis"))
    context.insert(FollowedGroup(acronym: "httpbis"))
    context.insert(FollowedGroup(acronym: "quic"))
    try context.save()

    try FollowedGroupStore.setFollowed("httpbis", false, in: context)
    #expect(try FollowedGroupStore.followedGroups(in: context) == ["quic"])
  }

  @Test func `deduplicating keeps one row per group`() throws {
    let container = try makeContainer()
    let context = container.mainContext
    context.insert(FollowedGroup(acronym: "httpbis"))
    context.insert(FollowedGroup(acronym: "httpbis"))
    try context.save()

    try UserData.deduplicate(context)
    #expect(try context.fetchCount(FetchDescriptor<FollowedGroup>()) == 1)
  }

  // MARK: - Mirror

  @Test func `a group followed is mirrored`() throws {
    let mirror = UserDataMirror(container: try makeContainer())
    mirror.start()
    #expect(mirror.followedGroups.isEmpty)

    try FollowedGroupStore.setFollowed("quic", true, in: mirror.container.mainContext)
    #expect(mirror.followedGroups == ["quic"])

    try FollowedGroupStore.setFollowed("quic", false, in: mirror.container.mainContext)
    #expect(mirror.followedGroups.isEmpty)
  }

  /// So the app compares as soon as a group is followed, here or on another device,
  /// whose follow arrives as a save of a context other than the main one.
  @Test func `a change to the followed groups is reported, from any context`() throws {
    let mirror = UserDataMirror(container: try makeContainer())
    var reports = 0
    mirror.onFollowedGroupsChanged = { reports += 1 }
    mirror.start()
    #expect(reports == 0)

    let synced = ModelContext(mirror.container)
    synced.insert(FollowedGroup(acronym: "quic"))
    try synced.save()
    #expect(mirror.followedGroups == ["quic"])
    #expect(reports == 1)

    // Following it again changes nothing, and reports nothing.
    try FollowedGroupStore.setFollowed("quic", true, in: mirror.container.mainContext)
    #expect(reports == 1)
  }

  // MARK: - Sidebar

  /// Ahead of the busiest groups, which then leave out the ones already shown.
  @Test func `followed groups come first, in order of name, then the top groups not followed`() {
    let groups = WorkingGroupFollowing.sidebarGroups(
      followed: ["tls", "quic"], top: ["httpbis", "tls", "dnsop"])
    #expect(groups == ["quic", "tls", "httpbis", "dnsop"])
  }

  @Test func `with nothing followed the sidebar lists the top groups`() {
    #expect(
      WorkingGroupFollowing.sidebarGroups(followed: [], top: ["httpbis", "tls"])
        == ["httpbis", "tls"])
  }

  /// A followed group is listed while the index loads, when there is no top list yet.
  @Test func `followed groups are listed without a top list`() {
    #expect(WorkingGroupFollowing.sidebarGroups(followed: ["quic"], top: []) == ["quic"])
  }

  // MARK: - Commands

  @Test func `the command says what it will do`() {
    #expect(
      WorkingGroupFollowing.command(isFollowed: false, locale: .english)
        == "Follow Working Group")
    #expect(
      WorkingGroupFollowing.command(isFollowed: true, locale: .english)
        == "Unfollow Working Group")
  }

  /// The index's word for an RFC from no group is not a group to follow.
  @Test func `only a named group can be followed`() {
    #expect(WorkingGroupFollowing.canFollow("httpbis"))
    #expect(!WorkingGroupFollowing.canFollow("NON WORKING GROUP"))
    #expect(!WorkingGroupFollowing.canFollow(""))
  }
}
