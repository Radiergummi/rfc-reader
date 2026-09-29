import Testing

@testable import RFCKit

/// An author's name as the reader shows it (#19, #25).
@Suite("Author")
struct AuthorTests {
  /// The legacy parser records an editor as "Editor" or "Ed.", the index and RFCXML
  /// as "editor"; all mean the same, and another role is not promoted to one.
  @Test func `an editor is marked as one, however the role is spelled`() {
    #expect(Author(name: "A. Author", role: "editor").displayName == "A. Author, Ed.")
    #expect(Author(name: "B. Author", role: "Ed.").displayName == "B. Author, Ed.")
    #expect(Author(name: "C. Author", role: "contributor").displayName == "C. Author")
    #expect(Author(name: "D. Author").displayName == "D. Author")
  }

  /// A title page's author column marks an editor as `, Ed.`, `, Ed`, `, Editor` or
  /// `,Ed.`. Only `, Ed.` was taken off the name, so `, Editor` stayed in it and
  /// became "A. Author, Editor, Ed."; `,Ed.` stayed too, and gave no role at all.
  @Test func `the legacy author column strips every editor suffix it accepts`() {
    for line in [
      "A. Author, Ed.", "A. Author, Ed", "A. Author, Editor", "A. Author,Ed.", "A. Author, Editor.",
    ] {
      let author = LegacyTextParser.author(in: line)
      #expect(author?.name == "A. Author", "\(line)")
      #expect(author?.isEditor == true, "\(line)")
    }
    let plain = LegacyTextParser.author(in: "B. C. O'Author-Name")
    #expect(plain?.name == "B. C. O'Author-Name")
    #expect(plain?.role == nil)
    #expect(LegacyTextParser.author(in: "Some Company, Inc.") == nil)
  }
}
