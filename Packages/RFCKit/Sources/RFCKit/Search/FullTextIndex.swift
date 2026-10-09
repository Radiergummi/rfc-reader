internal import CSQLite
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
  /// Where the matched words are, on Unicode scalar boundaries: a match may end inside
  /// a character, before a combining mark, so read them through `text.unicodeScalars`.
  public var matches: [Range<String.Index>]
}

/// Full-text search over document bodies (#37): one row per section, in SQLite FTS5,
/// ranked by flat BM25, as the plan on #37 settled. Built on the device from the
/// documents the app has parsed, so it carries no text that was not downloaded from
/// the RFC Editor on this device.
///
/// A section's text is its heading and its own blocks: prose, lists, tables, captions and
/// verbatim text, but not its subsections, which are rows of their own. The abstract
/// is a row too, anchored `abstract` as the reader anchors it. A bibliography and a
/// back-of-book index are left out: each is a list, of titles or of terms, which
/// answers no question and outranks the sections that do.
///
/// One connection, used from one task, as `CitationIndex` is: not `Sendable`. The
/// connection is the one unsafe thing it holds, and nothing outside sees it, so it
/// is `@safe` to use.
///
/// The schema:
///
///     meta (key, value)             -- `version`
///     documents (document)          -- every document indexed, `rfc8999`
///     sections (document, anchor, number, heading, body)   -- FTS5
///     section_rows (row, document)  -- which document each row of `sections` is
///
/// `section_rows` is what a document's rows are found by: `sections` cannot index
/// its `document` column, so deleting by it scanned every row of every document.
@safe public final class FullTextIndex {
  /// Raised whenever the tables or what a section's text is change: an index made
  /// under another version is emptied when it is opened. The app then indexes its
  /// stored bodies again; a document indexed by Index All RFCs, whose body was not
  /// kept, is only back once that run is made again.
  public static let version = 1

  /// The anchor the reader gives the abstract, which a hit in it opens.
  public static let abstractAnchor = "abstract"

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
    // A second connection writing, as the app's indexing may be while a search
    // reads, is waited for rather than failing at once.
    try check(unsafe sqlite3_busy_timeout(connection, 5_000))
    // A search reads while indexing writes, and each document indexed is a commit of
    // its own.
    try execute("PRAGMA journal_mode = WAL")
    // An index of this version is opened without the write lock, so a search is not
    // kept waiting behind indexing.
    guard try storedVersion() != String(version) else { return }
    // In one transaction, so a second connection opening the index at the same time
    // finds the version once this one has rebuilt the tables, and does not rebuild them
    // under it.
    try transaction {
      try execute("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
      guard try storedVersion() != String(version) else { return }
      try execute(
        """
        DROP TABLE IF EXISTS documents;
        DROP TABLE IF EXISTS sections;
        DROP TABLE IF EXISTS section_rows;
        CREATE TABLE documents (document TEXT PRIMARY KEY);
        CREATE VIRTUAL TABLE sections USING fts5(
          document UNINDEXED, anchor UNINDEXED, number UNINDEXED, heading, body,
          tokenize = 'unicode61 remove_diacritics 2'
        );
        CREATE TABLE section_rows (row INTEGER PRIMARY KEY, document TEXT NOT NULL);
        CREATE INDEX section_rows_by_document ON section_rows (document);
        """)
      try run("INSERT OR REPLACE INTO meta (key, value) VALUES ('version', ?)", String(version))
    }
  }

  deinit {
    unsafe sqlite3_close(connection)
  }

  /// The version the index was made under, nil for a new file.
  private func storedVersion() throws -> String? {
    guard try !strings("SELECT name FROM sqlite_master WHERE name = 'meta'").isEmpty else {
      return nil
    }
    return try strings("SELECT value FROM meta WHERE key = 'version'").first
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
      let record = try unsafe prepare(
        "INSERT INTO section_rows (row, document) VALUES (last_insert_rowid(), ?)")
      defer { unsafe sqlite3_finalize(record) }
      try unsafe bind(id.fileStem, at: 1, in: record)
      for row in Self.rows(of: document) {
        try check(unsafe sqlite3_reset(insert))
        try unsafe bind(id.fileStem, at: 1, in: insert)
        try unsafe bind(row.anchor, at: 2, in: insert)
        try unsafe bind(row.number, at: 3, in: insert)
        try unsafe bind(row.heading, at: 4, in: insert)
        try unsafe bind(row.body, at: 5, in: insert)
        try unsafe step(insert)
        try check(unsafe sqlite3_reset(record))
        try unsafe step(record)
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

  /// A document never indexed has no rows, and costs one lookup.
  private func deleteRows(of id: DocumentID) throws {
    guard try !strings("SELECT document FROM documents WHERE document = ?", id.fileStem).isEmpty
    else { return }
    try run(
      "DELETE FROM sections WHERE rowid IN (SELECT row FROM section_rows WHERE document = ?)",
      id.fileStem)
    try run("DELETE FROM section_rows WHERE document = ?", id.fileStem)
    try run("DELETE FROM documents WHERE document = ?", id.fileStem)
  }

  /// One row of `sections`, before it is written.
  struct Row: Equatable {
    var anchor: String
    var number: String?
    var heading: String
    var body: String
  }

  /// What is indexed of `document`: the abstract, unless a section of the body is
  /// the abstract already, as a converted legacy one may be; then every section that
  /// is not a bibliography or a back-of-book index.
  static func rows(of document: RFCDocument) -> [Row] {
    let sections = document.allSections.filter {
      !RFCXMLSerializer.isReferences($0) && !$0.holdsIndex
    }
    var rows: [Row] = []
    if !document.header.abstract.isEmpty,
      !document.allSections.contains(where: { $0.anchor == abstractAnchor })
    {
      rows.append(
        Row(
          anchor: abstractAnchor, number: nil, heading: "Abstract",
          body: text(of: document.header.abstract)))
    }
    rows += sections.map { section in
      Row(
        anchor: section.anchor, number: section.number, heading: section.titleText,
        body: text(of: section.blocks))
    }
    return rows
  }

  /// A section's own text, as it is searched: its blocks' prose, verbatim text and
  /// captions, the blocks nested in them included, but not its subsections'. Without
  /// the characters `snippet()` marks a match with, so one in a document is never
  /// read as a marker.
  static func text(of blocks: [Block]) -> String {
    let text = blocks.flattened.flatMap { block -> [String] in
      var runs = block.proseRuns.map(\.plainText)
      let caption: String? =
        switch block {
        case .figure(let figure): figure.title
        case .table(let table): table.title
        default: nil
        }
      if let caption { runs.append(caption) }
      if case .preformatted(let content) = block {
        runs.append(content.text)
      }
      return runs
    }
    .joined(separator: "\n")
    return String(text.unicodeScalars.filter { $0 != matchStart && $0 != matchEnd })
  }

  // MARK: - Searching

  /// The sections that hold every word of `query`, best first. A quoted run is a
  /// phrase; everything else is words, whatever FTS5 would make of it.
  public func search(_ query: String, limit: Int = 50) throws -> [SectionHit] {
    guard let match = Self.matchExpression(for: query) else { return [] }
    // `rank` is `bm25()` with no weights, and lets FTS5 sort the matches itself, so
    // `snippet()` runs for the rows returned only, not for every section that matched.
    // The snippet is the body's (column 4): left to choose, FTS5 takes a heading that
    // matches as often, which the result shows already.
    let statement = try unsafe prepare(
      """
      SELECT document, anchor, number, heading,
        snippet(sections, 4, char(57344), char(57345), '…', 16)
      FROM sections WHERE sections MATCH ? ORDER BY rank LIMIT ?
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
    // A NUL parts words: FTS5 reads its query only up to one, which would end it
    // inside a quoted string.
    let terms = SearchQuery.words(in: query.replacing("\u{0}", with: " "))
      .map(SearchQuery.unquoted)
      .filter { $0.contains { $0.isLetter || $0.isNumber } }
      .map { "\"" + $0.replacing("\"", with: "\"\"") + "\"" }
    return terms.isEmpty ? nil : terms.joined(separator: " ")
  }

  /// The private-use characters `snippet()` is asked to put around each match.
  private static let matchStart: Unicode.Scalar = "\u{E000}"
  private static let matchEnd: Unicode.Scalar = "\u{E001}"

  /// A snippet with its markers taken out and their places kept, and each run of white
  /// space, a verbatim block's line breaks and alignment, one space, none at either
  /// end. Read by scalar, not by character: a marker followed by a combining mark or a
  /// variation selector is one character with it.
  static func snippet(marked: String) -> Snippet {
    var scalars = String.UnicodeScalarView()
    var offsets: [Range<Int>] = []
    var start: Int?
    var pendingSpace = false
    for scalar in marked.unicodeScalars {
      switch scalar {
      case matchStart:
        if pendingSpace { scalars.append(" ") }
        pendingSpace = false
        start = scalars.count
      case matchEnd:
        if let begun = start { offsets.append(begun..<scalars.count) }
        start = nil
      case _ where scalar.properties.isWhitespace:
        pendingSpace = !scalars.isEmpty
      default:
        if pendingSpace { scalars.append(" ") }
        pendingSpace = false
        scalars.append(scalar)
      }
    }
    let text = String(scalars)
    let matches = offsets.map { range in
      let lower = text.unicodeScalars.index(text.startIndex, offsetBy: range.lowerBound)
      return lower..<text.unicodeScalars.index(lower, offsetBy: range.count)
    }
    return Snippet(text: text, matches: matches)
  }

  // MARK: - SQLite

  private var message: String {
    unsafe connection.flatMap { unsafe sqlite3_errmsg($0) }.map { unsafe String(cString: $0) }
      ?? "SQLite failed"
  }

  /// Takes the write lock at once: a transaction that reads first and then writes is
  /// refused at its first write while another connection writes, without waiting
  /// the busy timeout.
  private func transaction(_ body: () throws -> Void) throws {
    try execute("BEGIN IMMEDIATE")
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

  /// The first column of every row `sql` returns, with `values` bound in order. A
  /// failure throws rather than ending the rows early: an empty answer to the
  /// version check would empty the index, and to `indexed()` would index it all again.
  private func strings(_ sql: String, _ values: String...) throws -> [String] {
    let statement = try unsafe prepare(sql)
    defer { unsafe sqlite3_finalize(statement) }
    for (offset, value) in values.enumerated() {
      try unsafe bind(value, at: Int32(offset + 1), in: statement)
    }
    var rows: [String] = []
    while true {
      let result = unsafe sqlite3_step(statement)
      guard result == SQLITE_ROW else {
        guard result == SQLITE_DONE else { throw Failure(description: message) }
        return rows
      }
      if let value = unsafe column(0, of: statement) { rows.append(value) }
    }
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
    // Its length in bytes, rather than up to a NUL, so a NUL does not cut the text short.
    let length = Int32(text.utf8.count)
    try check(unsafe sqlite3_bind_text(statement, index, text, length, Self.transient))
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

extension Section {
  /// Whether this is the document's back-of-book index (`IndexBlock`).
  fileprivate var holdsIndex: Bool {
    blocks.contains { if case .index = $0 { true } else { false } }
  }
}
