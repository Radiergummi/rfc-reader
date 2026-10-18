internal import CSQLite
import Foundation

/// One connection to an SQLite database, through the system's SQLite (#864): what
/// `FullTextIndex`, corpus-build's `IndexDatabase` and the app's `CitationIndex` each
/// did for themselves, opening, running, binding and reading, done once. Every
/// failure is a `Failure` with SQLite's message.
///
/// Used from one task, as each of them is: not `Sendable`. The connection is the one
/// unsafe thing it holds, and nothing outside sees it, so it is `@safe` to use.
@safe public final class SQLiteDatabase {
  public struct Failure: Error, CustomStringConvertible {
    public let description: String
  }

  private var connection: OpaquePointer?

  /// Opens the database at `url`: read-write, making it if there is none, or
  /// `readOnly`, when a missing file is a failure rather than a new database.
  public init(contentsOf url: URL, readOnly: Bool = false) throws {
    let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
    // A failed open still hands back a connection, for its message; `deinit` closes it.
    guard unsafe sqlite3_open_v2(url.path, &connection, flags, nil) == SQLITE_OK else {
      throw failure
    }
    // A second connection writing, as the app's indexing may be while a search
    // reads, is waited for rather than failing at once.
    try check(unsafe sqlite3_busy_timeout(connection, 5_000))
  }

  deinit {
    unsafe sqlite3_close(connection)
  }

  /// Runs `sql`, which may be several statements, and returns nothing it reads.
  public func execute(_ sql: String) throws {
    guard unsafe sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
      throw failure
    }
  }

  /// Runs `body` in a transaction, committed when it returns and rolled back when it
  /// throws. It takes the write lock at once: a transaction that reads first and then
  /// writes is refused at its first write while another connection writes, without
  /// waiting the busy timeout.
  public func transaction(_ body: () throws -> Void) throws {
    try execute("BEGIN IMMEDIATE")
    do {
      try body()
      try execute("COMMIT")
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }

  /// Runs a statement that returns no rows, with `values` bound in order.
  public func run(_ sql: String, _ values: String?...) throws {
    let statement = try prepare(sql)
    for (offset, value) in values.enumerated() {
      try statement.bind(value, at: Int32(offset + 1))
    }
    _ = try statement.step()
  }

  /// The first column of every row `sql` returns, with `values` bound in order, a NULL
  /// left out. A failure throws rather than ending the rows early, where an empty
  /// answer would be taken for a true one.
  public func strings(_ sql: String, _ values: String...) throws -> [String] {
    let statement = try prepare(sql)
    for (offset, value) in values.enumerated() {
      try statement.bind(value, at: Int32(offset + 1))
    }
    var rows: [String] = []
    while try statement.step() {
      if let value = statement.text(at: 0) { rows.append(value) }
    }
    return rows
  }

  public func prepare(_ sql: String) throws -> Statement {
    var statement: OpaquePointer?
    guard unsafe sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
      throw failure
    }
    return unsafe Statement(statement, of: self)
  }

  /// A failure with the message of the connection's last error.
  private var failure: Failure {
    Failure(
      description: unsafe connection.flatMap { unsafe sqlite3_errmsg($0) }
        .map { unsafe String(cString: $0) } ?? "SQLite failed")
  }

  /// A failed bind leaves the parameter as it was, so a row would be written with the
  /// last one's value.
  private func check(_ result: Int32) throws {
    guard result == SQLITE_OK else { throw failure }
  }

  /// A prepared statement, finalized when it is released. It keeps its database open
  /// until then. Parameters and columns are numbered as SQLite numbers them:
  /// parameters from 1, columns from 0.
  @safe public final class Statement {
    private let statement: OpaquePointer?
    private let database: SQLiteDatabase

    fileprivate init(_ statement: OpaquePointer?, of database: SQLiteDatabase) {
      unsafe self.statement = statement
      self.database = database
    }

    deinit {
      unsafe sqlite3_finalize(statement)
    }

    /// Binds `text`, or NULL for nil. SQLite copies the text, since the Swift string it
    /// came from does not outlive the call.
    public func bind(_ text: String?, at index: Int32) throws {
      guard let text else {
        try database.check(unsafe sqlite3_bind_null(statement, index))
        return
      }
      // Its length in bytes, rather than up to a NUL, so a NUL does not cut the text short.
      let length = Int32(text.utf8.count)
      try database.check(
        unsafe sqlite3_bind_text(statement, index, text, length, SQLiteDatabase.transient))
    }

    public func bind(_ value: Double, at index: Int32) throws {
      try database.check(unsafe sqlite3_bind_double(statement, index, value))
    }

    public func bind(_ value: Int, at index: Int32) throws {
      try database.check(unsafe sqlite3_bind_int64(statement, index, Int64(value)))
    }

    /// Runs the statement to its next row: true while a row comes, false once it is
    /// done.
    public func step() throws -> Bool {
      switch unsafe sqlite3_step(statement) {
      case SQLITE_ROW: true
      case SQLITE_DONE: false
      default: throw database.failure
      }
    }

    /// Readies the statement to run again. Its bound values stay until they are bound
    /// again.
    public func reset() throws {
      try database.check(unsafe sqlite3_reset(statement))
    }

    /// The current row's column as text, nil when it is NULL.
    public func text(at column: Int32) -> String? {
      unsafe sqlite3_column_text(statement, column).map { unsafe String(cString: $0) }
    }

    public func double(at column: Int32) -> Double {
      unsafe sqlite3_column_double(statement, column)
    }

    public func integer(at column: Int32) -> Int {
      Int(unsafe sqlite3_column_int64(statement, column))
    }
  }

  /// `SQLITE_TRANSIENT`, which the C macro spells as a cast Swift cannot import.
  private static let transient = unsafe unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
