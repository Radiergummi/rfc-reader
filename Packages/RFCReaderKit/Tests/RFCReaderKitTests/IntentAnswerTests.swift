import RFCKit
import Testing

@testable import RFCReaderKit

/// What the App Intents say back, and the request a reader takes for them (#192).
@Suite("Intent answers")
struct IntentAnswerTests {
  @Test func `a count of requirements is said in words`() {
    #expect(
      IntentAnswer.requirements(0, in: "RFC 9110")
        == "There are no BCP 14 requirements in RFC 9110.")
    #expect(IntentAnswer.requirements(1, in: "RFC 9110") == "There is one requirement in RFC 9110.")
    #expect(
      IntentAnswer.requirements(12, in: "RFC 9110") == "There are 12 requirements in RFC 9110.")
  }

  @Test func `a definition names the identifier, its name and where it is defined`() {
    #expect(
      IntentAnswer.definition(
        of: "TLS alert 70", name: "protocol_version", definedIn: "RFC 8446, Section 6.2")
        == "TLS alert 70, protocol_version, is defined in RFC 8446, Section 6.2.")
    #expect(
      IntentAnswer.definition(
        of: "HTTP field Retry-After", name: nil, definedIn: "RFC 9110, Section 10.2.3")
        == "HTTP field Retry-After is defined in RFC 9110, Section 10.2.3.")
    #expect(
      IntentAnswer.definition(of: "HTTP status 499", name: nil, definedIn: nil)
        == "HTTP status 499 is in IANA's registry, which names no RFC for it.")
  }

  @Test func `a request is taken once, by its own document's reader`() {
    var request: DocumentRequest<String>? = DocumentRequest(id: .rfc(9110), value: "requirements")
    #expect(DocumentRequest.take(&request, for: .rfc(9112)) == nil)
    #expect(request != nil)
    #expect(DocumentRequest.take(&request, for: .rfc(9110)) == "requirements")
    #expect(request == nil)
    #expect(DocumentRequest.take(&request, for: .rfc(9110)) == nil)
  }
}
