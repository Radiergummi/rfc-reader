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

  /// What a citation inverts and a printed page's footer names (#375).
  @Test func `a surname is the name's last word`() {
    #expect(Author(name: "A. Writer").surname == "Writer")
    #expect(Author(name: "Anne B. Writer", role: "editor").surname == "Writer")
    #expect(Author(name: "Writer").surname == "Writer")
  }
}
