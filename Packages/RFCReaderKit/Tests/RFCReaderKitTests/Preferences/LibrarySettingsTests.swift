import RFCKit
import SwiftUI
import Testing

@testable import RFCReaderKit

/// The library's defaults in Settings (#713): what a new tab's list starts with.
@Suite("Library settings")
struct LibrarySettingsTests {
  private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
    let suite = "LibrarySettingsTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(defaults)
  }

  @Test func `nothing stored decodes to the defaults`() throws {
    try withDefaults { defaults in
      #expect(LibrarySettings(defaults: defaults) == LibrarySettings())
    }
  }

  /// With nothing changed in Settings, a new tab lists as it always has.
  @Test func `the defaults seed the options a tab has always started with`() {
    #expect(LibrarySettings().listOptions == ListOptions())
    #expect(LibrarySettings().showsAprilFirst)
    #expect(LibrarySettings().showsStatusBadges)
  }

  @Test func `every stored key decodes`() throws {
    try withDefaults { defaults in
      defaults.set(false, forKey: LibraryPreferences.showsObsoleteInListsKey)
      defaults.set(false, forKey: LibraryPreferences.showsObsoleteInSearchKey)
      defaults.set(ListOptions.Order.oldestFirst.rawValue, forKey: LibraryPreferences.orderKey)
      defaults.set(true, forKey: LibraryPreferences.searchesCurrentOnlyKey)
      defaults.set(PublicationStream.ietf.rawValue, forKey: LibraryPreferences.searchStreamKey)
      defaults.set(false, forKey: LibraryPreferences.showsAprilFirstKey)
      defaults.set(false, forKey: LibraryPreferences.showsStatusBadgesKey)

      let settings = LibrarySettings(defaults: defaults)
      #expect(!settings.showsObsoleteInLists)
      #expect(!settings.showsObsoleteInSearch)
      #expect(settings.order == .oldestFirst)
      #expect(settings.searchScope == SearchScope(currentOnly: true, stream: .ietf))
      #expect(!settings.showsAprilFirst)
      #expect(!settings.showsStatusBadges)
    }
  }

  @Test func `a stream this version does not know searches every stream`() throws {
    try withDefaults { defaults in
      defaults.set("NOSUCH", forKey: LibraryPreferences.searchStreamKey)
      #expect(LibrarySettings(defaults: defaults).searchScope.stream == nil)
    }
  }

  /// A new tab starts with what Settings says, and its View Options change it from there.
  @Test func `the settings seed a new tab's options`() {
    var settings = LibrarySettings()
    settings.showsObsoleteInLists = false
    settings.showsObsoleteInSearch = false
    settings.order = .oldestFirst
    settings.searchScope = SearchScope(currentOnly: true)
    settings.showsAprilFirst = false

    let options = settings.listOptions
    #expect(!options.showsObsolete)
    #expect(!options.showsObsoleteInSearch)
    #expect(options.order == .oldestFirst)
    #expect(options.searchScope == SearchScope(currentOnly: true))
    #expect(!options.showsAprilFirst)
    // Collections keep their own default, and Hide Read is a tab's own filter.
    #expect(options.collectionSort == .manual)
    #expect(!options.hidesRead)
  }
}
