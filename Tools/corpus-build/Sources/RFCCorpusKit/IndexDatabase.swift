import CSQLite
import Foundation
import RFCKit

/// The corpus's index database, `indexes.sqlite` (#174): what is computed over every
/// document offline, because no one document can say it, for the app to ship as a
/// pack. It holds metadata and anchors only, never RFC text: the full-text index is a
/// pack of its own (#37).
///
/// Written in one transaction, and only once `close()` commits it is it whole.
///
/// The schema:
///
///     meta (key, value)
///     citations (citing, cited, place, section, count, kind)
///
/// `meta` holds `schema` (`schemaVersion`) and whatever the build adds, such as the
/// packs' version. A citation's documents are `DocumentID.description`s (`RFC9110`);
/// its `place` is `abstract`, `section`, with the section's anchor in `section`, or
/// `bibliography`; its `kind` is a `ReferenceList.Kind`, or null for a citation no
/// entry names. See `Citation`.
public final class IndexDatabase {
  /// Raised when the tables change shape, so a reader can refuse a database it does
  /// not know.
  public static let schemaVersion = 1

  public struct Failure: Error, CustomStringConvertible {
    public let description: String
  }

  private var connection: OpaquePointer?
  private var insertCitation: OpaquePointer?

  /// Creates the database at `url`, replacing any file there.
  public init(creatingAt url: URL) throws {
    try? FileManager.default.removeItem(at: url)
    guard sqlite3_open(url.path, &connection) == SQLITE_OK else {
      let failure = Failure(description: Self.message(of: connection))
      sqlite3_close(connection)
      throw failure
    }
    try execute(
      """
      CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
      CREATE TABLE citations (
        citing TEXT NOT NULL,
        cited TEXT NOT NULL,
        place TEXT NOT NULL,
        section TEXT,
        count INTEGER NOT NULL,
        kind TEXT
      );
      BEGIN;
      """)
    insertCitation = try prepare(
      "INSERT INTO citations (citing, cited, place, section, count, kind) VALUES (?, ?, ?, ?, ?, ?)"
    )
    try setMeta("schema", to: String(Self.schemaVersion))
  }

  deinit {
    sqlite3_finalize(insertCitation)
    sqlite3_close(connection)
  }

  public func setMeta(_ key: String, to value: String) throws {
    let statement = try prepare("INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)")
    defer { sqlite3_finalize(statement) }
    bind(key, at: 1, in: statement)
    bind(value, at: 2, in: statement)
    try step(statement)
  }

  /// The citations `citing` makes, as `Citations.of` lists them.
  public func insert(_ citations: [Citation], citing: DocumentID) throws {
    let statement = insertCitation
    for citation in citations {
      sqlite3_reset(statement)
      bind(citing.description, at: 1, in: statement)
      bind(citation.cited.description, at: 2, in: statement)
      switch citation.place {
      case .abstract:
        bind("abstract", at: 3, in: statement)
        bind(nil, at: 4, in: statement)
      case .section(let anchor):
        bind("section", at: 3, in: statement)
        bind(anchor, at: 4, in: statement)
      case .bibliography:
        bind("bibliography", at: 3, in: statement)
        bind(nil, at: 4, in: statement)
      }
      sqlite3_bind_int64(statement, 5, Int64(citation.count))
      bind(citation.kind?.rawValue, at: 6, in: statement)
      try step(statement)
    }
  }

  /// Indexes what a reader looks up and commits: until this returns, the file holds
  /// nothing a reader should trust.
  public func close() throws {
    try execute(
      """
      CREATE INDEX citations_by_cited ON citations (cited);
      CREATE INDEX citations_by_citing ON citations (citing);
      COMMIT;
      VACUUM;
      """)
  }

  // MARK: - SQLite

  private func execute(_ sql: String) throws {
    guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
      throw Failure(description: Self.message(of: connection))
    }
  }

  private func prepare(_ sql: String) throws -> OpaquePointer? {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
      throw Failure(description: Self.message(of: connection))
    }
    return statement
  }

  private func step(_ statement: OpaquePointer?) throws {
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw Failure(description: Self.message(of: connection))
    }
  }

  /// SQLite copies the text, since the Swift string it came from does not outlive
  /// the call: `SQLITE_TRANSIENT`, which the C macro spells as a cast Swift cannot
  /// import.
  private func bind(_ text: String?, at index: Int32, in statement: OpaquePointer?) {
    guard let text else {
      sqlite3_bind_null(statement, index)
      return
    }
    sqlite3_bind_text(statement, index, text, -1, Self.transient)
  }

  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  private static func message(of connection: OpaquePointer?) -> String {
    connection.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "SQLite failed"
  }
}
