import CSQLite
import Foundation

/// A section found by `FullTextIndex.search`: where it is, what it is called, and the
/// words around the match.
public struct SectionHit: Sendable, Hashable {
  public var document: DocumentID
  /// The section's anchor, which opens the document there.
  public var anchor: String
  /// The section's number, `5.3` or `A`, or nil for an unnumbered one.
  public var number: String?
  public var heading: String
  public var snippet: Snippet
}

/// A few words of a section around where a query matched, with the matched words
/// marked, for a result row to set them apart.
public struct Snippet: Sendable, Hashable {
  public var text: String
  public var matches: [Range<String.Index>]
}

/// Full-text search over document bodies (#37): one row per section, in SQLite FTS5,
/// ranked by flat BM25, as the plan on #37 settled. Built on the device from the
/// documents the app has parsed, so it carries no text that was not downloaded from
/// the RFC Editor on this device.
///
/// A section's text is its heading and its own blocks: prose, lists, tables and
/// verbatim text, but not its subsections, which are rows of their own. A
/// bibliography is left out: it is a list of titles, which answers no question and
/// outranks the sections that do.
///
/// One connection, used from one task, as `CitationIndex` is: not `Sendable`. The
/// connection is the one unsafe thing it holds, and nothing outside sees it, so it
/// is `@safe` to use.
///
/// The schema:
///
///     meta (key, value)            -- `version`
///     documents (document)         -- every document indexed, `rfc8999`
///     sections (document, anchor, number, heading, body)   -- FTS5
@safe public final class FullTextIndex {
  /// Raised whenever the tables or what a section's text is change: an index made
  /// under another version is emptied when it is opened, and the app indexes its
  /// stored bodies again.
  public static let version = 1

  public struct Failure: Error, CustomStringConvertible {
    public let description: String
  }

  private var connection: OpaquePointer?

  /// Opens the index at `url`, making it if there is none.
  public convenience init(contentsOf url: URL) throws {
    try self.init(contentsOf: url, version: Self.version)
  }

  /// `version` is the one the index is held to, for a test to open it under another.
  init(contentsOf url: URL, version: Int) throws {
    // A failed open still hands back a connection, for its message; `deinit` closes it.
    guard unsafe sqlite3_open(url.path, &connection) == SQLITE_OK else {
      throw Failure(description: message)
    }
    try execute("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
    if try strings("SELECT value FROM meta WHERE key = 'version'").first != String(version) {
      try execute(
        """
        DROP TABLE IF EXISTS documents;
        DROP TABLE IF EXISTS sections;
        CREATE TABLE documents (document TEXT PRIMARY KEY);
        CREATE VIRTUAL TABLE sections USING fts5(
          document UNINDEXED, anchor UNINDEXED, number UNINDEXED, heading, body,
          tokenize = 'unicode61 remove_diacritics 2'
        );
        """)
      try run("INSERT OR REPLACE INTO meta (key, value) VALUES ('version', ?)", String(version))
    }
  }

  deinit {
    unsafe sqlite3_close(connection)
  }

  // MARK: - Writing

  /// Indexes `document`, replacing what was indexed of it before. One that does not
  /// say which RFC it is is refused: its hits could open nothing.
  public func add(_ document: RFCDocument) throws {
    guard let id = document.header.id else {
      throw Failure(description: "the document names no number")
    }
    try transaction {
      try deleteRows(of: id)
      let insert = try unsafe prepare(
        "INSERT INTO sections (document, anchor, number, heading, body) VALUES (?, ?, ?, ?, ?)")
      defer { unsafe sqlite3_finalize(insert) }
      for section in document.allSections where !RFCXMLSerializer.isReferences(section) {
        try check(unsafe sqlite3_reset(insert))
        try unsafe bind(id.fileStem, at: 1, in: insert)
        try unsafe bind(section.anchor, at: 2, in: insert)
        try unsafe bind(section.number, at: 3, in: insert)
        try unsafe bind(section.titleText, at: 4, in: insert)
        try unsafe bind(Self.text(of: section), at: 5, in: insert)
        try unsafe step(insert)
      }
      try run("INSERT INTO documents (document) VALUES (?)", id.fileStem)
    }
  }

  public func remove(_ id: DocumentID) throws {
    try transaction { try deleteRows(of: id) }
  }

  /// Every document indexed.
  public func indexed() throws -> Set<DocumentID> {
    Set(try strings("SELECT document FROM documents").compactMap(DocumentID.init(fileStem:)))
  }

  private func deleteRows(of id: DocumentID) throws {
    try run("DELETE FROM sections WHERE document = ?", id.fileStem)
    try run("DELETE FROM documents WHERE document = ?", id.fileStem)
  }

  /// A section's own text, as it is searched: its blocks' prose and verbatim text,
  /// the blocks nested in them included, but not its subsections'.
  static func text(of section: Section) -> String {
    section.blocks.flattened.flatMap { block -> [String] in
      var runs = block.proseRuns.map(\.plainText)
      if case .preformatted(let content) = block {
        runs.append(content.text)
      }
      return runs
    }
    .joined(separator: "\n")
  }

  // MARK: - Searching

  /// The sections that hold every word of `query`, best first. A quoted run is a
  /// phrase; everything else is words, whatever FTS5 would make of it.
  public func search(_ query: String, limit: Int = 50) throws -> [SectionHit] {
    guard let match = Self.matchExpression(for: query) else { return [] }
    let statement = try unsafe prepare(
      """
      SELECT document, anchor, number, heading,
        snippet(sections, -1, char(57344), char(57345), '…', 16)
      FROM sections WHERE sections MATCH ? ORDER BY bm25(sections) LIMIT ?
      """)
    defer { unsafe sqlite3_finalize(statement) }
    try unsafe bind(match, at: 1, in: statement)
    try check(unsafe sqlite3_bind_int64(statement, 2, Int64(limit)))
    var hits: [SectionHit] = []
    while true {
      let result = unsafe sqlite3_step(statement)
      guard result == SQLITE_ROW else {
        guard result == SQLITE_DONE else { throw Failure(description: message) }
        return hits
      }
      guard let id = unsafe column(0, of: statement).flatMap(DocumentID.init(fileStem:)),
        let anchor = unsafe column(1, of: statement)
      else { continue }
      hits.append(
        SectionHit(
          document: id, anchor: anchor, number: unsafe column(2, of: statement),
          heading: unsafe column(3, of: statement) ?? "",
          snippet: Self.snippet(marked: unsafe column(4, of: statement) ?? "")))
    }
  }

  /// `query` as an FTS5 match expression: each word, or each quoted run, as an FTS5
  /// string, so nothing typed is read as an operator, a column filter or a prefix.
  /// Nil when nothing in it is a word.
  static func matchExpression(for query: String) -> String? {
    let terms = SearchQuery.words(in: query)
      .map(SearchQuery.unquoted)
      .filter { $0.contains { $0.isLetter || $0.isNumber } }
      .map { "\"" + $0.replacing("\"", with: "\"\"") + "\"" }
    return terms.isEmpty ? nil : terms.joined(separator: " ")
  }

  /// The private-use characters `snippet()` is asked to put around each match.
  private static let matchStart: Character = "\u{E000}"
  private static let matchEnd: Character = "\u{E001}"

  /// A snippet with its markers taken out and their places kept.
  static func snippet(marked: String) -> Snippet {
    var text = ""
    var matches: [Range<String.Index>] = []
    var start: String.Index?
    for character in marked {
      switch character {
      case matchStart: start = text.endIndex
      case matchEnd:
        if let begun = start { matches.append(begun..<text.endIndex) }
        start = nil
      default: text.append(character)
      }
    }
    // Indices into the string as it was while being built are its indices now: it
    // was only ever appended to.
    return Snippet(text: text, matches: matches)
  }

  // MARK: - SQLite

  private var message: String {
    unsafe connection.flatMap { unsafe sqlite3_errmsg($0) }.map { unsafe String(cString: $0) }
      ?? "SQLite failed"
  }

  private func transaction(_ body: () throws -> Void) throws {
    try execute("BEGIN")
    do {
      try body()
      try execute("COMMIT")
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }

  private func execute(_ sql: String) throws {
    guard unsafe sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
      throw Failure(description: message)
    }
  }

  private func prepare(_ sql: String) throws -> OpaquePointer? {
    var statement: OpaquePointer?
    guard unsafe sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
      throw Failure(description: message)
    }
    return unsafe statement
  }

  /// Runs a statement that returns no rows, with `values` bound in order.
  private func run(_ sql: String, _ values: String...) throws {
    let statement = try unsafe prepare(sql)
    defer { unsafe sqlite3_finalize(statement) }
    for (offset, value) in values.enumerated() {
      try unsafe bind(value, at: Int32(offset + 1), in: statement)
    }
    try unsafe step(statement)
  }

  /// The first column of every row `sql` returns.
  private func strings(_ sql: String) throws -> [String] {
    let statement = try unsafe prepare(sql)
    defer { unsafe sqlite3_finalize(statement) }
    var values: [String] = []
    while unsafe sqlite3_step(statement) == SQLITE_ROW {
      if let value = unsafe column(0, of: statement) { values.append(value) }
    }
    return values
  }

  private func step(_ statement: OpaquePointer?) throws {
    guard unsafe sqlite3_step(statement) == SQLITE_DONE else {
      throw Failure(description: message)
    }
  }

  /// SQLite copies the text, since the Swift string it came from does not outlive
  /// the call: `SQLITE_TRANSIENT`, which the C macro spells as a cast Swift cannot
  /// import.
  private func bind(_ text: String?, at index: Int32, in statement: OpaquePointer?) throws {
    guard let text else {
      try check(unsafe sqlite3_bind_null(statement, index))
      return
    }
    try check(unsafe sqlite3_bind_text(statement, index, text, -1, Self.transient))
  }

  private func column(_ index: Int32, of statement: OpaquePointer?) -> String? {
    unsafe sqlite3_column_text(statement, index).map { unsafe String(cString: $0) }
  }

  /// A failed bind leaves the parameter as it was, so a row would be written with the
  /// last one's value.
  private func check(_ result: Int32) throws {
    guard result == SQLITE_OK else { throw Failure(description: message) }
  }

  private static let transient = unsafe unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
