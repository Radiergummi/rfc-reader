import CSQLite
import Foundation
import RFCCorpusKit
import RFCKit
import Testing

/// The corpus's index database (#174), read back through SQLite's own API, as a
/// reader in any language would.
@Suite
final class IndexDatabaseTests {
  /// One per test, removed with everything written into it.
  private let directory = FileManager.default.temporaryDirectory
    .appending(path: "index-database-\(UUID().uuidString)")

  init() throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  deinit {
    try? FileManager.default.removeItem(at: directory)
  }

  private static let citations = [
    Citation(cited: .rfc(7807), place: .abstract, count: 1, kind: .normative),
    Citation(cited: .rfc(7252), place: .section("basic"), count: 4, kind: .normative),
    Citation(
      cited: .rfc(6082), place: .section("detailed-semantics"), count: 1, kind: .informative),
    Citation(cited: .rfc(783), place: .bibliography, count: 1, kind: .unknown),
    Citation(cited: .rfc(1247), place: .abstract, count: 2, kind: nil),
  ]

  /// A database written to a fresh temporary file, closed, and opened again.
  private func written(_ write: (IndexDatabase) throws -> Void) throws -> OpaquePointer? {
    let url = directory.appending(path: "indexes.sqlite")
    let database = try IndexDatabase(creatingAt: url)
    try write(database)
    try database.close()
    var connection: OpaquePointer?
    #expect(sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
    return connection
  }

  /// Every row of `sql`, each column as text or nil.
  private static func rows(_ sql: String, in connection: OpaquePointer?) -> [[String?]] {
    var statement: OpaquePointer?
    #expect(sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK)
    defer { sqlite3_finalize(statement) }
    var rows: [[String?]] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      rows.append(
        (0..<sqlite3_column_count(statement)).map { column in
          sqlite3_column_text(statement, column).map { String(cString: $0) }
        })
    }
    return rows
  }

  @Test func `citations read back as they were written`() throws {
    let connection = try written { try $0.insert(Self.citations, citing: .rfc(9290)) }
    defer { sqlite3_close(connection) }
    #expect(
      Self.rows(
        "SELECT citing, cited, place, section, count, kind FROM citations ORDER BY rowid",
        in: connection)
        == [
          ["RFC9290", "RFC7807", "abstract", nil, "1", "normative"],
          ["RFC9290", "RFC7252", "section", "basic", "4", "normative"],
          ["RFC9290", "RFC6082", "section", "detailed-semantics", "1", "informative"],
          ["RFC9290", "RFC783", "bibliography", nil, "1", "unknown"],
          ["RFC9290", "RFC1247", "abstract", nil, "2", nil],
        ])
  }

  /// What the index is for: which documents cite one, which no document can say.
  @Test func `the documents citing one are a lookup`() throws {
    let connection = try written { database in
      try database.insert(Self.citations, citing: .rfc(9290))
      try database.insert(
        [Citation(cited: .rfc(7252), place: .section("intro"), count: 1, kind: .normative)],
        citing: .rfc(9177))
    }
    defer { sqlite3_close(connection) }
    #expect(
      Self.rows(
        "SELECT DISTINCT citing FROM citations WHERE cited = 'RFC7252' ORDER BY citing",
        in: connection) == [["RFC9177"], ["RFC9290"]])
  }

  @Test func `the schema version and the build's metadata are kept`() throws {
    let connection = try written { try $0.setMeta("version", to: "2026.10") }
    defer { sqlite3_close(connection) }
    #expect(
      Self.rows("SELECT key, value FROM meta ORDER BY key", in: connection)
        == [["schema", String(IndexDatabase.schemaVersion)], ["version", "2026.10"]])
  }

  @Test func `writing over a database replaces it`() throws {
    let url = directory.appending(path: "indexes.sqlite")
    for citing in [DocumentID.rfc(1), .rfc(2)] {
      let database = try IndexDatabase(creatingAt: url)
      try database.insert(Self.citations, citing: citing)
      try database.close()
    }
    var connection: OpaquePointer?
    #expect(sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
    defer { sqlite3_close(connection) }
    #expect(Self.rows("SELECT DISTINCT citing FROM citations", in: connection) == [["RFC2"]])
  }

  /// A failed open is an error, not a crash: SQLite hands back a connection even then,
  /// and it is closed once.
  @Test func `a database that cannot be created is an error`() {
    let url = directory.appending(path: "missing/indexes.sqlite")
    #expect(throws: IndexDatabase.Failure.self) { try IndexDatabase(creatingAt: url) }
  }
}
