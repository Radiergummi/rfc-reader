/// The shape of the corpus's index database, `indexes.sqlite` (#174), which
/// corpus-build's `IndexDatabase` writes and the app's `CitationIndex` reads: one
/// statement of it, so the two cannot drift apart unnoticed. Plain strings, so RFCKit
/// gains no SQLite (docs/DATA_PIPELINE.md); what each table holds is described at
/// `IndexDatabase`.
public enum IndexSchema {
  /// Raised when the tables change shape, so a reader can refuse a database it does
  /// not know. Written to `meta` under `schema`.
  public static let version = 3

  /// The tables, created empty.
  public static let tables = """
    CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
    CREATE TABLE citations (
      citing TEXT NOT NULL,
      cited TEXT NOT NULL,
      place TEXT NOT NULL,
      section TEXT,
      count INTEGER NOT NULL,
      kind TEXT
    );
    CREATE TABLE successions (
      old TEXT NOT NULL,
      old_section TEXT NOT NULL,
      new TEXT NOT NULL,
      new_section TEXT NOT NULL,
      score REAL NOT NULL
    );
    CREATE TABLE amendments (
      amended TEXT NOT NULL,
      section TEXT NOT NULL,
      amending TEXT NOT NULL,
      amending_section TEXT
    );

    """

  /// One citation, its six values bound in order.
  public static let insertCitation =
    "INSERT INTO citations (citing, cited, place, section, count, kind) VALUES (?, ?, ?, ?, ?, ?)"

  /// One succession, its five values bound in order.
  public static let insertSuccession =
    "INSERT INTO successions (old, old_section, new, new_section, score) VALUES (?, ?, ?, ?, ?)"

  /// One amendment, its four values bound in order.
  public static let insertAmendment =
    "INSERT INTO amendments (amended, section, amending, amending_section) VALUES (?, ?, ?, ?)"
}
