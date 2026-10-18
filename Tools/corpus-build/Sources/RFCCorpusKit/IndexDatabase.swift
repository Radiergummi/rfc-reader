import CSQLite
import Foundation
import RFCKit

/// The corpus's index database, `indexes.sqlite` (#174): what is computed over every
/// document offline, because no one document can say it, for the app to ship as a
/// pack. It holds metadata and anchors only, never RFC text: the full-text index is
/// built on the device (#37).
///
/// Written in one transaction, and only once `close()` commits it is it whole.
///
/// The tables are `IndexSchema`'s, shared with the app's reader: `meta`,
/// `citations`, `successions` and `amendments`. `meta` holds
/// `schema` (`IndexSchema.version`) and whatever the build adds, such as the
/// packs' version. A citation's documents are `DocumentID.description`s (`RFC9110`);
/// its `place` is `abstract`, `section`, with the section's anchor in `section`, or
/// `bibliography`; its `kind` is a `ReferenceList.Kind`, or null for a citation no
/// entry names. See `Citation`. A succession is a section of an obsoleted document
/// and the section of the document obsoleting it that replaces it, both by anchor,
/// with how alike the two are. See `AlignedSection`. An amendment is a section of
/// one document, as the citation names it, and the document amending it, with the
/// anchor of the section that says so, or null for its abstract. See `Amendment`.
public final class IndexDatabase {
  public struct Failure: Error, CustomStringConvertible {
    public let description: String
  }

  private var connection: OpaquePointer?
  private var insertCitation: OpaquePointer?
  private var insertSuccession: OpaquePointer?
  private var insertAmendment: OpaquePointer?

  /// Creates the database at `url`, replacing any file there.
  public init(creatingAt url: URL) throws {
    try? FileManager.default.removeItem(at: url)
    // A failed open still hands back a connection, for its message; `deinit`
    // closes it, as it closes any other.
    guard sqlite3_open(url.path, &connection) == SQLITE_OK else {
      throw Failure(description: Self.message(of: connection))
    }
    try execute(IndexSchema.tables + "BEGIN;")
    insertCitation = try prepare(IndexSchema.insertCitation)
    insertSuccession = try prepare(IndexSchema.insertSuccession)
    insertAmendment = try prepare(IndexSchema.insertAmendment)
    try setMeta("schema", to: String(IndexSchema.version))
  }

  deinit {
    sqlite3_finalize(insertCitation)
    sqlite3_finalize(insertSuccession)
    sqlite3_finalize(insertAmendment)
    sqlite3_close(connection)
  }

  public func setMeta(_ key: String, to value: String) throws {
    let statement = try prepare("INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)")
    defer { sqlite3_finalize(statement) }
    try bind(key, at: 1, in: statement)
    try bind(value, at: 2, in: statement)
    try step(statement)
  }

  /// The citations `citing` makes, as `Citations.of` lists them.
  public func insert(_ citations: [Citation], citing: DocumentID) throws {
    let statement = insertCitation
    for citation in citations {
      try check(sqlite3_reset(statement))
      try bind(citing.description, at: 1, in: statement)
      try bind(citation.cited.description, at: 2, in: statement)
      switch citation.place {
      case .abstract:
        try bind("abstract", at: 3, in: statement)
        try bind(nil, at: 4, in: statement)
      case .section(let anchor):
        try bind("section", at: 3, in: statement)
        try bind(anchor, at: 4, in: statement)
      case .bibliography:
        try bind("bibliography", at: 3, in: statement)
        try bind(nil, at: 4, in: statement)
      }
      try check(sqlite3_bind_int64(statement, 5, Int64(citation.count)))
      try bind(citation.kind?.rawValue, at: 6, in: statement)
      try step(statement)
    }
  }

  /// The sections of an obsoleted document and their successors' sections, as
  /// `SectionAlignment.pairs` lists them.
  public func insert(_ successions: [AlignedSection]) throws {
    let statement = insertSuccession
    for succession in successions {
      try check(sqlite3_reset(statement))
      try bind(succession.old.description, at: 1, in: statement)
      try bind(succession.oldSection, at: 2, in: statement)
      try bind(succession.new.description, at: 3, in: statement)
      try bind(succession.newSection, at: 4, in: statement)
      try check(sqlite3_bind_double(statement, 5, succession.score))
      try step(statement)
    }
  }

  /// The sections of other documents a document amends, as `Amendments.links` lists
  /// them.
  public func insert(_ amendments: [Amendment]) throws {
    let statement = insertAmendment
    for amendment in amendments {
      try check(sqlite3_reset(statement))
      try bind(amendment.amended.description, at: 1, in: statement)
      try bind(amendment.section, at: 2, in: statement)
      try bind(amendment.amending.description, at: 3, in: statement)
      try bind(amendment.amendingSection, at: 4, in: statement)
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
      CREATE INDEX successions_by_old ON successions (old);
      CREATE INDEX successions_by_new ON successions (new);
      CREATE INDEX amendments_by_amended ON amendments (amended);
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
  private func bind(_ text: String?, at index: Int32, in statement: OpaquePointer?) throws {
    guard let text else {
      try check(sqlite3_bind_null(statement, index))
      return
    }
    try check(sqlite3_bind_text(statement, index, text, -1, Self.transient))
  }

  /// A failed bind leaves the parameter as it was, so a row would be written with the
  /// last one's value; it has to stop the build instead.
  private func check(_ result: Int32) throws {
    guard result == SQLITE_OK else {
      throw Failure(description: Self.message(of: connection))
    }
  }

  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  private static func message(of connection: OpaquePointer?) -> String {
    connection.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "SQLite failed"
  }
}
