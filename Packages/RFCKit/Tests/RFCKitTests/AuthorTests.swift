import Foundation
import Testing

@testable import RFCKit

/// An author's name as the reader shows it (#19, #25).
@Suite("Author")
struct AuthorTests {
  /// The legacy parser reads an editor as "Editor" or "Ed.", the index and RFCXML
  /// as "editor"; all mean the same, and another role is not promoted to one.
  @Test(arguments: ["editor", "Editor", "Ed.", "Ed", "ed."])
  func `an editor's role is read however it is spelled`(_ spelling: String) {
    #expect(Author.Role(parsing: spelling) == .editor)
  }

  @Test(arguments: ["contributor", "", "Director"])
  func `another role is not an editor's`(_ spelling: String) {
    #expect(Author.Role(parsing: spelling) == nil)
  }

  @Test func `an editor is marked as one`() {
    #expect(Author(name: "A. Author", role: .editor).displayName == "A. Author, Ed.")
    #expect(Author(name: "D. Author").displayName == "D. Author")
  }

  /// A reference's authors were names with the editorship written into them as
  /// `, Ed.`, which the serializer cut back off by its length. They are authors now,
  /// and an editor survives the round trip as one.
  @Test func `a reference's editor survives a round trip`() throws {
    let original = try Fixtures.document("rfc8999.xml")
    let reparsed = try RFCXMLParser.parse(Data(RFCXMLSerializer().serialize(original).utf8))
    for document in [original, reparsed] {
      let entry = try #require(
        document.referenceLists.flatMap(\.entries).first { $0.anchor == "QUIC-TRANSPORT" })
      #expect(
        entry.authors == [
          Author(name: "Jana Iyengar", role: .editor),
          Author(name: "Martin Thomson", role: .editor),
        ])
    }
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

  /// What a citation inverts and a printed page's footer names (#375).
  @Test func `a surname is the name's last word`() {
    #expect(Author(name: "A. Writer").surname == "Writer")
    #expect(Author(name: "Anne B. Writer", role: .editor).surname == "Writer")
    #expect(Author(name: "Writer").surname == "Writer")
  }
}
