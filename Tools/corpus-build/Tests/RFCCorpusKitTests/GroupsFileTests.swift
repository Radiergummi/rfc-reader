import Foundation
import RFCCorpusKit
import RFCKit
import Testing

/// `corpus-build groups` (#363): datatracker's groups, roles and people, as the API
/// sends them, made into `groups.json`. The JSON here is written in the API's shape,
/// as `DatatrackerTests` writes its listings, trimmed to the fields that are read.
@Suite("Groups file")
struct GroupsFileTests {
  private static let groupsJSON = """
    {"meta": {"next": "/api/v1/group/group/?format=json&order_by=id&limit=1000&offset=1000"},
     "objects": [
       {"id": 1718, "acronym": "httpbis", "name": "HTTP",
        "type": "/api/v1/name/grouptypename/wg/", "state": "/api/v1/name/groupstatename/active/",
        "parent": "/api/v1/group/group/2412/",
        "list_archive": "http://lists.w3.org/Archives/Public/ietf-http-wg/",
        "charter": "/api/v1/doc/document/charter-ietf-httpbis/"},
       {"id": 2412, "acronym": "wit", "name": "Web and Internet Transport",
        "type": "/api/v1/name/grouptypename/area/", "state": "/api/v1/name/groupstatename/active/",
        "parent": "/api/v1/group/group/2/", "list_archive": "", "charter": null},
       {"id": 900, "acronym": "urnbis", "name": "Uniform Resource Names, Revised",
        "type": "/api/v1/name/grouptypename/wg/", "state": "/api/v1/name/groupstatename/conclude/",
        "parent": "/api/v1/group/group/2412/", "list_archive": "", "charter": null},
       {"id": 31, "acronym": "cfrg", "name": "Crypto Forum",
        "type": "/api/v1/name/grouptypename/rg/", "state": "/api/v1/name/groupstatename/active/",
        "parent": "/api/v1/group/group/3/",
        "list_archive": "https://mailarchive.ietf.org/arch/browse/cfrg/", "charter": null},
       {"id": 3, "acronym": "irtf", "name": "Internet Research Task Force",
        "type": "/api/v1/name/grouptypename/irtf/", "state": "/api/v1/name/groupstatename/active/",
        "parent": null, "list_archive": "", "charter": null}
     ]}
    """

  private static let rolesJSON = """
    {"meta": {"next": null},
     "objects": [
       {"group": "/api/v1/group/group/1718/", "person": "/api/v1/person/person/119325/",
        "name": "/api/v1/name/rolename/chair/"},
       {"group": "/api/v1/group/group/1718/", "person": "/api/v1/person/person/103881/",
        "name": "/api/v1/name/rolename/chair/"},
       {"group": "/api/v1/group/group/900/", "person": "/api/v1/person/person/5/",
        "name": "/api/v1/name/rolename/chair/"}
     ]}
    """

  private func groups() throws -> [Datatracker.ListedGroup] {
    try Datatracker.decoder().decode(Datatracker.GroupPage.self, from: Data(Self.groupsJSON.utf8))
      .objects
  }

  private func roles() throws -> [Datatracker.Role] {
    try Datatracker.decoder().decode(Datatracker.RolePage.self, from: Data(Self.rolesJSON.utf8))
      .objects
  }

  @Test func `a group listing decodes, with its type, state and parent`() throws {
    let httpbis = try #require(try groups().first)
    #expect(httpbis.acronym == "httpbis")
    #expect(httpbis.typeSlug == "wg")
    #expect(httpbis.stateSlug == "active")
    #expect(httpbis.parentID == 2412)
    #expect(httpbis.charterName == "charter-ietf-httpbis")
    #expect(httpbis.archive?.absoluteString == "http://lists.w3.org/Archives/Public/ietf-http-wg/")
  }

  /// An empty archive is none, not a URL to nowhere, and so is one that is not a web
  /// page: older groups record an address or a word there.
  @Test func `an archive that is not a web page is none`() throws {
    #expect(try groups().first { $0.acronym == "urnbis" }?.archive == nil)
    func archive(_ value: String) throws -> URL? {
      let json = """
        {"meta": {"next": null}, "objects": [{"id": 1, "acronym": "x", "name": "X",
          "type": null, "state": null, "parent": null, "list_archive": "\(value)", "charter": null}]}
        """
      return try Datatracker.decoder().decode(Datatracker.GroupPage.self, from: Data(json.utf8))
        .objects.first?.archive
    }
    #expect(try archive("none") == nil)
    #expect(try archive("mailto:wg@ietf.org") == nil)
    #expect(try archive("https://mailarchive.ietf.org/arch/browse/x/") != nil)
  }

  /// Datatracker allows a group's type and state to be null; such a group decodes, and
  /// does not fail its page.
  @Test func `a group with no type or state decodes`() throws {
    let json = """
      {"meta": {"next": null}, "objects": [{"id": 1, "acronym": "x", "name": "X",
        "type": null, "state": null, "parent": null, "list_archive": null, "charter": null}]}
      """
    let group = try #require(
      try Datatracker.decoder().decode(Datatracker.GroupPage.self, from: Data(json.utf8))
        .objects.first)
    #expect(group.typeSlug == "unknown")
    #expect(group.stateSlug == "unknown")
  }

  /// A run that could not name most chairs is datatracker failing, not the chairs
  /// leaving; a few failures are left out for a day.
  @Test func `a run that could not name most chairs is not published`() {
    #expect(GroupsFile.chairsAreNamed(requested: 170, failed: 3))
    #expect(GroupsFile.chairsAreNamed(requested: 0, failed: 0))
    #expect(!GroupsFile.chairsAreNamed(requested: 170, failed: 170))
  }

  @Test func `chair roles are grouped by group, as person URIs`() throws {
    let chairs = GroupsFile.chairs(try roles())
    #expect(
      chairs[1718]
        == ["/api/v1/person/person/119325/", "/api/v1/person/person/103881/"])
  }

  @Test func `a person's URI is fetched as JSON`() {
    #expect(
      Datatracker.person("/api/v1/person/person/119325/").absoluteString
        == "https://datatracker.ietf.org/api/v1/person/person/119325/?format=json")
  }

  /// Only the groups the index names, matched in any case; an area named for a group in
  /// it; current chairs for an active group, by name and sorted, and none for one that
  /// has concluded, whose roles datatracker keeps.
  @Test func `the file holds the groups the index names, with their areas and chairs`() throws {
    let names = [
      "/api/v1/person/person/119325/": "Tommy Pauly",
      "/api/v1/person/person/103881/": "Mark Nottingham",
      "/api/v1/person/person/5/": "Someone Earlier",
    ]
    let file = GroupsFile.build(
      groups: try groups(), named: ["HTTPBIS", "urnbis", "cfrg", "nosuchgroup"],
      chairs: GroupsFile.chairs(try roles()), people: names,
      generatedAt: Date(timeIntervalSince1970: 1_790_000_000))

    #expect(file.groups.keys.sorted() == ["cfrg", "httpbis", "urnbis"])
    let httpbis = try #require(file.group("httpbis"))
    #expect(httpbis.name == "HTTP")
    #expect(httpbis.area == "Web and Internet Transport")
    #expect(httpbis.chairs == ["Mark Nottingham", "Tommy Pauly"])
    #expect(httpbis.charter == "charter-ietf-httpbis")
    #expect(file.group("urnbis")?.state == "conclude")
    #expect(file.group("urnbis")?.chairs == [])
    // A research group's parent is the IRTF, not an area.
    #expect(file.group("cfrg")?.area == nil)
  }

  /// Which people to look up: the chairs of the active groups kept, each once.
  @Test func `only the chairs of the active groups kept are looked up`() throws {
    let people = GroupsFile.peopleToFetch(
      groups: try groups(), named: ["httpbis", "urnbis"], chairs: GroupsFile.chairs(try roles()))
    #expect(people == ["/api/v1/person/person/103881/", "/api/v1/person/person/119325/"])
  }

  /// A real change in the groups does not lose half of them; a broken query does.
  @Test func `a file that lost more than half its groups is not published`() {
    func file(_ count: Int) -> WorkingGroups {
      WorkingGroups(
        generatedAt: .now,
        groups: (0..<count).map {
          WorkingGroups.Group(
            acronym: "g\($0)", name: "G", type: "wg", state: "active", area: nil, chairs: [],
            listArchive: nil, charter: nil)
        })
    }
    #expect(GroupsFile.mayPublish(file(400), replacing: file(500), allowShrink: false))
    #expect(!GroupsFile.mayPublish(file(200), replacing: file(500), allowShrink: false))
    #expect(GroupsFile.mayPublish(file(200), replacing: file(500), allowShrink: true))
    #expect(GroupsFile.mayPublish(file(1), replacing: nil, allowShrink: false))
  }
}
