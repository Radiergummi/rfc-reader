import Foundation
import RFCCorpusKit
import Testing

/// The pieces of datatracker's API the scanner reads, decoded as the API sends them.
@Suite("Datatracker")
struct DatatrackerTests {
  @Test func `a listing page decodes, with state IDs and the stream's slug`() throws {
    let json = """
      {"meta": {"next": "/api/v1/doc/document/?format=json&limit=100&offset=100", "total_count": 150},
       "objects": [{"name": "draft-ietf-example-thing", "rev": "07",
                    "states": ["/api/v1/doc/state/150/", "/api/v1/doc/state/1/", "/api/v1/doc/state/38/"],
                    "stream": "/api/v1/name/streamname/ietf/", "time": "2026-09-01T10:00:00Z"}]}
      """
    let page = try Datatracker.decoder().decode(Datatracker.DraftPage.self, from: Data(json.utf8))
    let draft = try #require(page.objects.first)
    #expect(draft.name == "draft-ietf-example-thing")
    #expect(draft.rev == "07")
    #expect(draft.stateIDs == [1, 38, 150])
    #expect(draft.streamSlug == "ietf")
    #expect(
      Datatracker.next(page.meta.next)?.absoluteString
        == "https://datatracker.ietf.org/api/v1/doc/document/?format=json&limit=100&offset=100")
  }

  /// Unordered, the pages are separate queries that need not agree on an order, so a
  /// draft could be listed twice or not at all.
  @Test func `the listing is ordered, so its pages do not overlap`() throws {
    let components = try #require(
      URLComponents(url: Datatracker.draftsFirstPage, resolvingAgainstBaseURL: false))
    #expect(components.queryItems?.contains(URLQueryItem(name: "order_by", value: "id")) == true)
  }

  @Test func `the last page has no next`() {
    #expect(Datatracker.next(nil) == nil)
  }

  @Test func `the state table keys each state by ID, with its type's slug`() throws {
    let json = """
      {"meta": {"next": null},
       "objects": [{"id": 150, "type": "/api/v1/doc/statetype/draft-iesg/", "slug": "idexists", "name": "I-D Exists"}]}
      """
    let page = try Datatracker.decoder().decode(Datatracker.StatePage.self, from: Data(json.utf8))
    #expect(Datatracker.stateTable([page]) == [150: DraftState("draft-iesg", "idexists")])
  }

  /// Datatracker writes microseconds for recent revisions and none for old ones.
  @Test func `a record decodes publish dates with and without fractional seconds`() throws {
    let json = """
      {"name": "draft-example-thing", "rev": "05",
       "group": {"name": "Individual Submissions", "type": "Individual", "acronym": "none"},
       "intended_std_level": "Informational", "stream": "IETF",
       "rev_history": [{"name": "draft-example-thing", "rev": "04", "published": "2014-04-14T13:39:29+00:00"},
                       {"name": "draft-example-thing", "rev": "05", "published": "2025-12-01T18:27:41.095128+00:00"}]}
      """
    let record = try Datatracker.decoder().decode(
      Datatracker.DraftRecord.self, from: Data(json.utf8))
    #expect(record.published(rev: "04") == Date(timeIntervalSince1970: 1_397_482_769))
    #expect(record.published(rev: "05") == Date(timeIntervalSince1970: 1_764_613_661))
    #expect(record.intendedStdLevel == "Informational")
    #expect(record.groupAcronym == nil, "\"none\" is no group")
  }

  @Test func `a record in a working group names it`() throws {
    let json = """
      {"group": {"name": "Example", "type": "WG", "acronym": "example"}, "intended_std_level": null, "rev_history": []}
      """
    let record = try Datatracker.decoder().decode(
      Datatracker.DraftRecord.self, from: Data(json.utf8))
    #expect(record.groupAcronym == "example")
    #expect(record.intendedStdLevel == nil)
  }

  @Test func `a draft's header is fetched from the archive`() {
    #expect(
      Datatracker.draft("draft-example-thing", rev: "05", extension: "xml").absoluteString
        == "https://www.ietf.org/archive/id/draft-example-thing-05.xml")
    #expect(
      Datatracker.record("draft-example-thing").absoluteString
        == "https://datatracker.ietf.org/doc/draft-example-thing/doc.json")
  }
}
