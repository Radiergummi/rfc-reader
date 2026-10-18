import Foundation
import Testing

@testable import RFCReaderKit

/// The AppleScript dictionary and the code that answers it name the same codes
/// (#762): a code changed in one and not the other makes a script's enumerator mean
/// nothing, with no error to say so.
@Suite("Script codes")
struct ScriptCodeTests {
  /// The enumerators of the dictionary's `enumeration` named `name`, by name.
  private static func enumerators(_ name: String) throws -> [String: String] {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("../../../../../App/RFCReader/Scripting/RFCReader.sdef")
      .standardizedFileURL
    let sdef = try String(contentsOf: url, encoding: .utf8)
    let opening = try #require(sdef.range(of: "<enumeration name=\"\(name)\""))
    let closing = try #require(
      sdef.range(of: "</enumeration>", range: opening.upperBound..<sdef.endIndex))
    let body = sdef[opening.upperBound..<closing.lowerBound]
    var result: [String: String] = [:]
    for match in body.matches(of: /<enumerator name="([^"]+)" code="([^"]{4})"/) {
      result[String(match.1)] = String(match.2)
    }
    return result
  }

  @Test func `every placement is the dictionary's, by name and code`() throws {
    let declared = try Self.enumerators("placement")
    #expect(declared.count == ScriptPlacement.allCases.count)
    for placement in ScriptPlacement.allCases {
      let code = try #require(declared[placement.name])
      #expect(ScriptCode.value(code) == placement.code)
      #expect(ScriptPlacement(code: placement.code) == placement)
    }
  }

  @Test func `every inspector pane is the dictionary's, by name and code`() throws {
    let declared = try Self.enumerators("inspector pane")
    #expect(declared.count == ScriptPane.allCases.count)
    for pane in ScriptPane.allCases {
      let code = try #require(declared[pane.name])
      #expect(ScriptCode.value(code) == pane.code)
      #expect(ScriptPane(code: pane.code) == pane)
    }
  }
}
