import Foundation
import RFCKit
import SQLite3
import Testing

@testable import RFCReaderKit

@Suite("Citation index")
struct CitationIndexTests {
  /// One row of the `citations` table; its section and count are never read.
  struct Row {
    var citing: String
    var cited: String
    var kind: String?
    var place: String

    init(_ citing: String, _ cited: String, _ kind: String?, place: String = "section") {
      self.citing = citing
      self.cited = cited
      self.kind = kind
      self.place = place
    }
  }

  struct WriteFailed: Error {}

  /// An `indexes.sqlite` written in the test, in the shape corpus-build's
  /// `IndexDatabase` writes it, removed with the directory it is in.
  final class Database {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "CitationIndexTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    var url: URL { directory.appending(path: CitationIndex.fileName) }

    /// `rows` in the order the index writes them.
    init(
      schema: String = String(CitationIndex.schemaVersion), documents: Int,
      rows: [Row]
    ) throws {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      var connection: OpaquePointer?
      guard sqlite3_open(url.path, &connection) == SQLITE_OK else { throw WriteFailed() }
      defer { sqlite3_close(connection) }
      var sql = """
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
        CREATE TABLE citations (
          citing TEXT NOT NULL, cited TEXT NOT NULL, place TEXT NOT NULL,
          section TEXT, count INTEGER NOT NULL, kind TEXT);
        INSERT INTO meta VALUES ('schema', '\(schema)'), ('documents', '\(documents)');
        """
      for row in rows {
        let kind = row.kind.map { "'\($0)'" } ?? "NULL"
        sql +=
          "INSERT INTO citations VALUES ('\(row.citing)', '\(row.cited)', '\(row.place)', NULL, 1, \(kind));\n"
      }
      guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else { throw WriteFailed() }
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
  }

  @Test func `a document's normative references keep their citation order`() throws {
    let database = try Database(
      documents: 10,
      rows: [
        Row("RFC1", "RFC5", "normative"),
        Row("RFC1", "RFC3", "informative"),
        Row("RFC1", "RFC2", "normative"),
        Row("RFC1", "RFC5", "normative", place: "bibliography"),
        Row("RFC1", "RFC4", nil),
        Row("RFC2", "RFC1", "normative"),
      ])
    let index = try CitationIndex(contentsOf: database.url)
    let references = try index.references(of: .rfc(1))
    #expect(references.normative == [.rfc(5), .rfc(2)])
    #expect(!references.isUndeclared)
  }

  @Test func `a document with only unknown lists declares no kind`() throws {
    let database = try Database(
      documents: 10,
      rows: [
        Row("RFC1", "RFC2", "unknown"),
        Row("RFC3", "RFC2", "unknown"),
        Row("RFC3", "RFC4", "informative"),
      ])
    let index = try CitationIndex(contentsOf: database.url)
    #expect(try index.references(of: .rfc(1)) == .init(normative: [], isUndeclared: true))
    #expect(try index.references(of: .rfc(3)) == .init(normative: [], isUndeclared: false))
    #expect(try index.references(of: .rfc(9)) == .init(normative: [], isUndeclared: false))
  }

  @Test func `the assumed documents are those cited normatively by more than the share`() throws {
    // 100 documents: more than 2 citing documents makes a document assumed.
    let database = try Database(
      documents: 100,
      rows: [
        Row("RFC10", "RFC2119", "normative"),
        Row("RFC11", "RFC2119", "normative"),
        Row("RFC12", "RFC2119", "normative", place: "bibliography"),
        Row("RFC12", "RFC2119", "normative"),
        Row("RFC10", "RFC3986", "normative"),
        Row("RFC11", "RFC3986", "normative"),
        Row("RFC12", "RFC3986", "informative"),
        Row("RFC10", "BCP14", "normative"),
        Row("RFC11", "BCP14", "normative"),
        Row("RFC13", "BCP14", "normative"),
      ])
    let index = try CitationIndex(contentsOf: database.url)
    #expect(try index.assumed(share: 0.02) == [.rfc(2119), DocumentID(series: .bcp, number: 14)])
  }

  @Test func `a database of another schema is refused`() throws {
    let database = try Database(schema: "1", documents: 1, rows: [])
    #expect(throws: CitationIndex.Failure.unknownSchema("1")) {
      try CitationIndex(contentsOf: database.url)
    }
  }

  @Test func `a missing database is refused, not created`() throws {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "CitationIndexTests-\(UUID().uuidString).sqlite")
    #expect(throws: CitationIndex.Failure.self) { try CitationIndex(contentsOf: url) }
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  @Test func `a path is walked from the database`() async throws {
    let database = try Database(
      documents: 100,
      rows: [
        Row("RFC1", "RFC2", "normative"),
        Row("RFC1", "RFC2119", "normative"),
        Row("RFC2", "RFC3", "normative"),
        Row("RFC2", "RFC2119", "normative"),
        Row("RFC3", "RFC2119", "normative"),
      ])
    let path = try await CitationIndex.readingPath(from: .rfc(1), depth: 4, in: database.url)
    #expect(path.steps.map(\.document) == [.rfc(3), .rfc(2), .rfc(1)])
    #expect(path.assumed == [.rfc(2119)])
  }
}
