import Foundation
import RFCKit

/// The citation graph of the `indexes` pack, bundled or installed, read-only
/// (#189): the first reader of the `indexes.sqlite` that corpus-build's
/// `IndexDatabase` writes.
///
/// One connection, used from one task: open it, ask, and let it go. It is not
/// `Sendable`; `readingPath(from:depth:in:)` does all three for a caller off the
/// main actor.
public final class CitationIndex {
  /// The database's name inside the pack.
  public static let fileName = "indexes.sqlite"
  /// The share of the corpus that has to cite a document normatively for the
  /// document to be assumed: more than 2%, about 200 documents, decided on #189.
  public static let assumedShare = 0.02

  public enum Failure: Error, Equatable {
    /// The file is missing, or could not be read as a database.
    case unreadable(String)
    /// The database's `meta.schema`, or nil when it has none.
    case unknownSchema(String?)
    case query(String)
  }

  private let database: SQLiteDatabase

  public init(contentsOf url: URL) throws {
    // Read-only, and never created: a missing pack is a failure, not an empty index.
    do {
      database = try SQLiteDatabase(contentsOf: url, readOnly: true)
    } catch let failure as SQLiteDatabase.Failure {
      throw Failure.unreadable(failure.description)
    }
    let schema: String?
    do {
      schema = try strings("SELECT value FROM meta WHERE key = 'schema'").first
    } catch Failure.query(let message) {
      // SQLite opens lazily: a file that is not a database fails at the first query.
      throw Failure.unreadable(message)
    }
    guard schema == String(IndexSchema.version) else { throw Failure.unknownSchema(schema) }
  }

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
    try rows(sql, binding: values) { $0.text(at: 0) }.compactMap(\.self)
  }

  private func pairs(_ sql: String, binding values: [String]) throws -> [(String, String?)] {
    try rows(sql, binding: values) { statement in
      statement.text(at: 0).map { ($0, statement.text(at: 1)) }
    }.compactMap(\.self)
  }

  /// Every row of `sql`, read by `read`, with `values` bound in order. What SQLite
  /// refuses is a `Failure.query`.
  private func rows<Row>(
    _ sql: String, binding values: [String], _ read: (SQLiteDatabase.Statement) -> Row
  ) throws -> [Row] {
    do {
      let statement = try database.prepare(sql)
      for (index, value) in values.enumerated() {
        try statement.bind(value, at: Int32(index + 1))
      }
      var rows: [Row] = []
      while try statement.step() {
        rows.append(read(statement))
      }
      return rows
    } catch let failure as SQLiteDatabase.Failure {
      throw Failure.query(failure.description)
    }
  }
}
