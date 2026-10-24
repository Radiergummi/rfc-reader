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
  public typealias Failure = SQLiteDatabase.Failure

  private let database: SQLiteDatabase
  private let insertCitation: SQLiteDatabase.Statement
  private let insertSuccession: SQLiteDatabase.Statement
  private let insertAmendment: SQLiteDatabase.Statement

  /// Creates the database at `url`, replacing any file there.
  public init(creatingAt url: URL) throws {
    try? FileManager.default.removeItem(at: url)
    database = try SQLiteDatabase(contentsOf: url)
    try database.execute(IndexSchema.tables + "BEGIN;")
    insertCitation = try database.prepare(IndexSchema.insertCitation)
    insertSuccession = try database.prepare(IndexSchema.insertSuccession)
    insertAmendment = try database.prepare(IndexSchema.insertAmendment)
    try setMeta("schema", to: String(IndexSchema.version))
  }

  public func setMeta(_ key: String, to value: String) throws {
    try database.run("INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)", key, value)
  }

  /// The citations `citing` makes, as `Citations.of` lists them.
  public func insert(_ citations: [Citation], citing: DocumentID) throws {
    let statement = insertCitation
    for citation in citations {
      try statement.reset()
      try statement.bind(citing.description, at: 1)
      try statement.bind(citation.cited.description, at: 2)
      switch citation.place {
      case .abstract:
        try statement.bind("abstract", at: 3)
        try statement.bind(nil, at: 4)
      case .section(let anchor):
        try statement.bind("section", at: 3)
        try statement.bind(anchor, at: 4)
      case .bibliography:
        try statement.bind("bibliography", at: 3)
        try statement.bind(nil, at: 4)
      }
      try statement.bind(citation.count, at: 5)
      try statement.bind(citation.kind?.rawValue, at: 6)
      try statement.step()
    }
  }

  /// The sections of an obsoleted document and their successors' sections, as
  /// `SectionAlignment.pairs` lists them.
  public func insert(_ successions: [AlignedSection]) throws {
    let statement = insertSuccession
    for succession in successions {
      try statement.reset()
      try statement.bind(succession.old.description, at: 1)
      try statement.bind(succession.oldSection, at: 2)
      try statement.bind(succession.new.description, at: 3)
      try statement.bind(succession.newSection, at: 4)
      try statement.bind(succession.score, at: 5)
      try statement.step()
    }
  }

  /// The sections of other documents a document amends, as `Amendments.links` lists
  /// them.
  public func insert(_ amendments: [Amendment]) throws {
    let statement = insertAmendment
    for amendment in amendments {
      try statement.reset()
      try statement.bind(amendment.amended.description, at: 1)
      try statement.bind(amendment.section, at: 2)
      try statement.bind(amendment.amending.description, at: 3)
      try statement.bind(amendment.amendingSection, at: 4)
      try statement.step()
    }
  }

  /// Indexes what a reader looks up and commits: until this returns, the file holds
  /// nothing a reader should trust.
  public func close() throws {
    try database.execute(
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
}
