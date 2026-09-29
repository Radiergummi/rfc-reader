import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

/// Where a click on a reference goes. Both of the reader's hardest bugs were decisions
/// like this one written in the App target, where a test could only re-implement them.
@Suite("Link destination")
struct LinkDestinationTests {
  private let current = DocumentID(series: .rfc, number: 9110)
  private let other = DocumentID(series: .rfc, number: 8446)

  private func resolve(_ string: String, _ activation: LinkActivation = .here) -> LinkDestination {
    LinkDestination.resolve(URL(string: string)!, from: current, activation: activation)
  }

  // MARK: - Inside this document

  @Test func `an anchor jumps within the document`() {
    #expect(resolve("\(DocumentTextBuilder.anchorScheme):section-4.2") == .jump("section-4.2"))
  }

  /// The rule the enum exists to pin: a jump inside this document has nowhere else
  /// to go, so a modifier must not turn it into a second tab of the same document
  /// scrolled elsewhere.
  @Test func `an anchor still jumps when command is held`() {
    #expect(
      resolve("\(DocumentTextBuilder.anchorScheme):section-4.2", .newTab(inBackground: true))
        == .jump("section-4.2"))
  }

  /// The body does not hold the bibliography — the panel does — so a citation of
  /// an entry that names no RFC had nothing to scroll to and did nothing.
  @Test func `a citation of a bibliography entry reveals it`() {
    #expect(
      resolve("\(DocumentTextBuilder.referenceScheme):IEEE.802.3_2018")
        == .reference("IEEE.802.3_2018"))
  }

  /// A reference to a section of the document already on screen scrolls rather than
  /// re-opening what is already open.
  @Test func `a section of this document scrolls instead of opening`() {
    #expect(resolve("rfc://9110#section-4.2") == .jump("4.2"))
  }

  /// Without a section there is nothing to scroll to, so it opens as any link would.
  @Test func `this document without a section opens normally`() {
    #expect(resolve("rfc://9110") == .document(RFCLink(id: current)))
  }

  // MARK: - Another document

  @Test func `another document opens in place`() {
    #expect(resolve("rfc://8446#section-2") == .document(RFCLink(id: other, section: "2")))
  }

  @Test func `a web reference resolves the same way as the app scheme`() {
    #expect(resolve("https://www.rfc-editor.org/rfc/rfc8446") == .document(RFCLink(id: other)))
  }

  // MARK: - Modifiers

  /// A section of *this* document is still a document worth its own tab when asked
  /// for one — unlike an anchor, it names something the reader can open. The scroll
  /// shortcut is for following in place only.
  @Test func `a section of this document still gets its own tab when asked`() {
    let asked = resolve("rfc://9110#section-4.2", .newTab(inBackground: true))
    #expect(asked == .document(RFCLink(id: current, section: "4.2")))
  }

  // MARK: - Not ours

  @Test(
    arguments: [
      "https://example.com/spec",
      "mailto:someone@example.com",
    ])
  func `anything that is not an RFC is left to the system`(input: String) {
    #expect(resolve(input) == .unhandled)
  }
}
