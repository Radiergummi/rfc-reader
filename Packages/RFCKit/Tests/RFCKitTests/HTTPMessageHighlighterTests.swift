import Foundation
import Testing

@testable import RFCKit

@Suite("Highlighting: HTTP messages")
struct HTTPMessageHighlighterTests {
  private func tokens(_ text: String) -> [SyntaxToken] {
    HTTPMessageHighlighter().tokens(in: text)
  }

  @Test func `a request line is a method, a target and a version`() {
    let text = "GET /items?id=1 HTTP/1.1\nHost: www.example.com\n"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.kind(of: "GET", in: text) == .keyword)
    #expect(tokens.kind(of: "/items?id=1", in: text) == .string)
    #expect(tokens.kind(of: "HTTP/1.1", in: text) == .keyword)
    #expect(tokens.kind(of: "Host", in: text) == .name)
    #expect(tokens.kind(of: "www.example.com", in: text) == .plain)
  }

  @Test func `a status line is a version and a code`() {
    let text = "HTTP/1.1 404 Not Found\nContent-Length: 0"
    let tokens = tokens(text)
    #expect(tokens.kind(of: "HTTP/1.1", in: text) == .keyword)
    #expect(tokens.kind(of: "404", in: text) == .number)
    #expect(tokens.kind(of: "Content-Length", in: text) == .name)
  }

  @Test func `fields without a start line are fields`() {
    let text = "Cache-Control: max-age=60\nVary: Accept"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .name, in: text) == ["Cache-Control", "Vary"])
  }

  @Test func `a message set in from the margin is read as one`() {
    let text = "  POST /events HTTP/1.1\n  Content-Type: text/plain\n"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.kind(of: "POST", in: text) == .keyword)
    #expect(tokens.kind(of: "Content-Type", in: text) == .name)
  }

  @Test func `a status without its version is a code`() {
    let text = "206 Partial Content\nContent-Range: bytes 0-9/100"
    let tokens = tokens(text)
    #expect(tokens.kind(of: "206", in: text) == .number)
    #expect(tokens.kind(of: "Content-Range", in: text) == .name)
  }

  @Test func `a pseudo-header field is a name`() {
    let text = ":method = GET\n:path = /"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .name, in: text) == [":method", ":path"])
  }

  @Test func `a body is lexed as the content type with parameters says`() {
    let text =
      "HTTP/1.1 400 Bad Request\nContent-Type: application/problem+json; charset=utf-8\n\n{\"title\": \"Bad\"}"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.kind(of: #""title""#, in: text) == .name)
    #expect(tokens.kind(of: #""Bad""#, in: text) == .string)
  }

  @Test func `an XML body is lexed as XML`() {
    let text = "POST / HTTP/1.1\nContent-Type: application/xml\n\n<a b=\"c\"/>"
    #expect(tokens(text).kind(of: "<a", in: text) == .name)
  }

  @Test func `a body with no content type is plain`() {
    let text = "HTTP/1.1 200 OK\n\n{\"title\": \"x\"}"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.kind(of: #""title""#, in: text) == .plain)
  }

  @Test func `a second message after a body is read as a message`() {
    let text =
      "GET / HTTP/1.1\nHost: example.com\n\nHTTP/1.1 200 OK\nContent-Type: application/json\n\n{\"a\": 1}"
    let tokens = tokens(text)
    #expect(tokens.cover(text))
    #expect(tokens.text(of: .keyword, in: text) == ["GET", "HTTP/1.1", "HTTP/1.1"])
    #expect(tokens.kind(of: "200", in: text) == .number)
    #expect(tokens.kind(of: #""a""#, in: text) == .name)
  }

  @Test func `consecutive status lines are two messages`() {
    let source = NSString(string: "HTTP/1.1 100 Continue\nHTTP/1.1 200 OK\n")
    #expect(HTTPMessageHighlighter.messages(in: source).count == 2)
  }

  @Test func `an empty block has no messages`() {
    #expect(HTTPMessageHighlighter.messages(in: NSString(string: "")).isEmpty)
    #expect(tokens("").isEmpty)
  }
}
