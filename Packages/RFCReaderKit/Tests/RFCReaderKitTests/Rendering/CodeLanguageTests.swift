import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

@Suite("Code language names")
struct CodeLanguageTests {
  @Test(arguments: [
    ("application/jsonpath", "JSON Path"),
    ("http-message", "HTTP Message"),
    ("http-message-new", "HTTP Message"),
    ("yangtree", "YANG Tree"),
    ("cbor-diag", "CBOR Diagnostic Notation"),
    ("x509", "X.509"),
  ])
  func `a type that reads badly as it is gets its language's name`(type: String, name: String) {
    #expect(CodeLanguage.name(of: type) == name)
  }

  @Test func `a type is looked up whatever its case`() {
    #expect(CodeLanguage.name(of: "Application/JSONPath") == "JSON Path")
  }

  @Test(arguments: [
    (" message/http ; msgtype=\"request\"", "HTTP Message"),
    ("cbordiag", "CBOR Diagnostic Notation"),
  ])
  func `a type is looked up as the renderers read it`(type: String, name: String) {
    #expect(CodeLanguage.name(of: type) == name)
  }

  @Test(arguments: ["abnf", "yang", "CDDL", "rust"])
  func `any other type is shown as it is`(type: String) {
    #expect(CodeLanguage.name(of: type) == type)
  }

  @Test func `a code sample typed as a media type is labeled with its language`() {
    let content = Preformatted(
      kind: .sourceCode, text: "$.a[0]", type: "application/jsonpath")
    let built = DocumentTextBuilder.build(
      Fixtures.document(.preformatted(content)), style: ReadingStyle())
    #expect(built.text.string.contains("JSON PATH"))
    #expect(!built.text.string.contains("APPLICATION/JSONPATH"))
  }
}
