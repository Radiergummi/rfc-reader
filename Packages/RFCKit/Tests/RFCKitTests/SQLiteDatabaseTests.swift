import Foundation
import Testing

@testable import RFCKit

/// The SQLite helper the full-text index, the corpus's index database and the app's
/// citation index share (#864), over a database of the test's own.
///
/// A class, so the file is removed when the test ends, as in `FullTextIndexTests`.
@Suite("SQLite database")
final class SQLiteDatabaseTests {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "SQLiteDatabaseTests-\(UUID().uuidString).sqlite")

  deinit {
    for suffix in ["", "-wal", "-shm"] {
      try? FileManager.default.removeItem(at: URL(filePath: url.path + suffix))
    }
  }

  func database() throws -> SQLiteDatabase {
    let database = try SQLiteDatabase(contentsOf: url)
    try database.execute("CREATE TABLE IF NOT EXISTS rows (name TEXT, score REAL, count INTEGER)")
    return database
  }

  @Test func `bound values are read back as they were bound`() throws {
    let database = try database()
    let insert = try database.prepare("INSERT INTO rows (name, score, count) VALUES (?, ?, ?)")
    try insert.bind("überall", at: 1)
    try insert.bind(0.75, at: 2)
    try insert.bind(Int(Int32.max) + 1, at: 3)
    #expect(try insert.step() == false)

    let select = try database.prepare("SELECT name, score, count FROM rows")
    #expect(try select.step())
    #expect(select.text(at: 0) == "überall")
    #expect(select.double(at: 1) == 0.75)
    #expect(select.integer(at: 2) == Int(Int32.max) + 1)
    #expect(try select.step() == false)
  }

  @Test func `text with a NUL in it is read back whole`() throws {
    let database = try database()
    try database.run("INSERT INTO rows (name) VALUES (?)", "a\u{0}b")
    #expect(try database.strings("SELECT name FROM rows") == ["a\u{0}b"])
  }

  @Test func `a statement reset is bound and run again`() throws {
    let database = try database()
    let insert = try database.prepare("INSERT INTO rows (name) VALUES (?)")
    for name in ["a", "b"] {
      try insert.reset()
      try insert.bind(name, at: 1)
      try insert.step()
    }
    #expect(try database.strings("SELECT name FROM rows ORDER BY name") == ["a", "b"])
  }

  @Test func `a NULL column is read as nil and left out of strings`() throws {
    let database = try database()
    try database.run("INSERT INTO rows (name) VALUES (?)", nil)
    try database.run("INSERT INTO rows (name) VALUES (?)", "named")

    let select = try database.prepare("SELECT name FROM rows ORDER BY rowid")
    #expect(try select.step())
    #expect(select.text(at: 0) == nil)
    #expect(try database.strings("SELECT name FROM rows") == ["named"])
  }

  @Test func `a transaction a throw ends is rolled back`() throws {
    struct Stop: Error {}
    let database = try database()
    #expect(throws: Stop.self) {
      try database.transaction {
        try database.run("INSERT INTO rows (name) VALUES (?)", "kept?")
        throw Stop()
      }
    }
    #expect(try database.strings("SELECT name FROM rows").isEmpty)

    try database.transaction { try database.run("INSERT INTO rows (name) VALUES (?)", "kept") }
    #expect(try database.strings("SELECT name FROM rows") == ["kept"])
  }

  @Test func `a database opened read-only refuses a write`() throws {
    _ = try database()
    let reader = try SQLiteDatabase(contentsOf: url, readOnly: true)
    #expect(try reader.strings("SELECT name FROM rows").isEmpty)
    #expect(throws: SQLiteDatabase.Failure.self) {
      try reader.run("INSERT INTO rows (name) VALUES (?)", "refused")
    }
  }

  @Test func `a missing database opened read-only is refused, not created`() {
    #expect(throws: SQLiteDatabase.Failure.self) {
      try SQLiteDatabase(contentsOf: self.url, readOnly: true)
    }
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  @Test func `a failure carries SQLite's message`() throws {
    let database = try database()
    let error = #expect(throws: SQLiteDatabase.Failure.self) {
      try database.execute("SELECT * FROM missing")
    }
    #expect(error?.description.contains("no such table") == true)
  }
}
