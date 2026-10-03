import Foundation
import RFCKit
import SQLite3

/// The citation graph of the installed `indexes` pack, read-only (#189): the first
/// reader of the `indexes.sqlite` that corpus-build's `IndexDatabase` writes.
///
/// One connection, used from one task: open it, ask, and let it go. It is not
/// `Sendable`; `readingPath(from:depth:in:)` does all three for a caller off the
/// main actor.
public final class CitationIndex {
  /// The database's name inside the pack.
  public static let fileName = "indexes.sqlite"
  /// The `IndexDatabase.schemaVersion` this reads; any other is refused.
  public static let schemaVersion = 2
  /// The share of the corpus that has to cite a document normatively for the
  /// document to be assumed: more than 2%, about 200 documents, decided on #189.
  public static let assumedShare = 0.02

  public enum Failure: Error, Equatable {
    /// The file could not be opened as a database, or is missing.
    case unreadable(String)
    /// The database's `meta.schema`, or nil when it has none.
    case unknownSchema(String?)
    case query(String)
  }

  private var connection: OpaquePointer?

  public init(contentsOf url: URL) throws {
    // Read-only, and never created: a missing pack is a failure, not an empty index.
    guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      let message = Self.message(of: connection)
      sqlite3_close(connection)
      connection = nil
      throw Failure.unreadable(message)
    }
    let schema: String?
    do {
      schema = try strings("SELECT value FROM meta WHERE key = 'schema'").first
    } catch {
      throw Failure.unknownSchema(nil)
    }
    guard schema == String(Self.schemaVersion) else { throw Failure.unknownSchema(schema) }
  }

  deinit { sqlite3_close(connection) }

  /// What `id` cites normatively, each document once, in the order the index wrote
  /// its citations: document order, the bibliography's uncited entries last.
  public func references(of id: DocumentID) throws -> ReadingPath.References {
    let rows = try pairs(
      "SELECT cited, kind FROM citations WHERE citing = ? ORDER BY rowid", binding: [id.description]
    )
    var normative: [DocumentID] = []
    var declares = false
    var hasUnknown = false
    for (cited, kind) in rows {
      switch kind {
      case ReferenceList.Kind.normative.rawValue:
        declares = true
        if let cited = DocumentID(parsing: cited), !normative.contains(cited) {
          normative.append(cited)
        }
      case ReferenceList.Kind.informative.rawValue:
        declares = true
      case ReferenceList.Kind.unknown.rawValue:
        hasUnknown = true
      default:
        break
      }
    }
    return ReadingPath.References(normative: normative, isUndeclared: hasUnknown && !declares)
  }

  /// The documents cited normatively by more than `share` of the documents the index
  /// read.
  public func assumed(share: Double = assumedShare) throws -> Set<DocumentID> {
    guard
      let documents = try strings("SELECT value FROM meta WHERE key = 'documents'").first
        .flatMap(Int.init)
    else { return [] }
    let threshold = Int((Double(documents) * share).rounded(.down))
    // The threshold is written into the query, not bound: a bound value is text, and
    // SQLite orders every integer below every text.
    let cited = try strings(
      """
      SELECT cited FROM citations WHERE kind = ?
      GROUP BY cited HAVING COUNT(DISTINCT citing) > \(threshold)
      """,
      binding: [ReferenceList.Kind.normative.rawValue])
    return Set(cited.compactMap(DocumentID.init(parsing:)))
  }

  /// Opens the database at `url`, walks the path from `root`, and closes it.
  @concurrent
  public static func readingPath(
    from root: DocumentID, depth: Int = ReadingPath.defaultDepth, in url: URL
  ) async throws -> ReadingPath {
    let index = try CitationIndex(contentsOf: url)
    return try ReadingPath.walk(
      from: root, depth: depth, assumed: index.assumed(), references: index.references(of:))
  }

  // MARK: - SQLite

  private func strings(_ sql: String, binding values: [String] = []) throws -> [String] {
    try rows(sql, binding: values) { statement in Self.text(statement, 0) }.compactMap(\.self)
  }

  private func pairs(_ sql: String, binding values: [String]) throws -> [(String, String?)] {
    try rows(sql, binding: values) { statement in
      Self.text(statement, 0).map { ($0, Self.text(statement, 1)) }
    }.compactMap(\.self)
  }

  private func rows<Row>(
    _ sql: String, binding values: [String], _ read: (OpaquePointer) -> Row
  ) throws -> [Row] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK,
      let statement
    else { throw Failure.query(Self.message(of: connection)) }
    defer { sqlite3_finalize(statement) }
    for (index, value) in values.enumerated() {
      guard sqlite3_bind_text(statement, Int32(index + 1), value, -1, Self.transient) == SQLITE_OK
      else { throw Failure.query(Self.message(of: connection)) }
    }
    var rows: [Row] = []
    while true {
      switch sqlite3_step(statement) {
      case SQLITE_ROW: rows.append(read(statement))
      case SQLITE_DONE: return rows
      default: throw Failure.query(Self.message(of: connection))
      }
    }
  }

  private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
    sqlite3_column_text(statement, column).map { String(cString: $0) }
  }

  /// SQLite copies a bound value before the call returns.
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  private static func message(of connection: OpaquePointer?) -> String {
    connection.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "SQLite failed"
  }
}
