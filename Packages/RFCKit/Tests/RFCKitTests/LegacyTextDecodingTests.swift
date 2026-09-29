import Foundation
import Testing

@testable import RFCKit

/// How a legacy text file's bytes become text. 34 of the older documents are
/// Windows-1252 rather than UTF-8, and every reader of the text format -- the parser,
/// the app's original-text view, corpus-build -- decodes them through one function, so
/// none of them shows a replacement character where another shows the accent.
@Suite
struct LegacyTextDecodingTests {
  @Test func `bytes in UTF-8 decode as UTF-8`() {
    let bytes = Data("J. Müller, “Editor”".utf8)

    #expect(LegacyTextParser.text(decoding: bytes) == "J. Müller, “Editor”")
  }

  @Test func `bytes in Windows-1252 decode as Windows-1252, not as replacement characters`() {
    // "J. Andr\u{E9}, \u{201C}Memo\u{201D}" in Windows-1252: é is 0xE9, the curly
    // quotes 0x93 and 0x94, none of them valid UTF-8 on its own.
    let bytes =
      Data([0x4A, 0x2E, 0x20, 0x41, 0x6E, 0x64, 0x72, 0xE9, 0x2C, 0x20, 0x93])
      + Data("Memo".utf8) + Data([0x94])

    #expect(LegacyTextParser.text(decoding: bytes) == "J. André, “Memo”")
  }

  @Test func `bytes that are neither still decode`() {
    // 0x81 is unassigned in Windows-1252 and invalid UTF-8. What it becomes is the
    // platform's business -- Foundation on Linux may map it where Apple's refuses it
    // -- but the text around it survives either way.
    let bytes = Data("Page ".utf8) + Data([0x81])

    #expect(LegacyTextParser.text(decoding: bytes).hasPrefix("Page "))
  }
}
