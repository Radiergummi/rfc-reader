import Foundation
import RFCKit
import Testing

@testable import RFCReaderKit

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// The contract `BuiltDocument`'s `@unchecked Sendable` rests on (#128): a build runs
/// off the main actor, and nothing in what it returns can be written by anyone once
/// it reaches the main actor.
///
/// Not `@MainActor`, unlike the other builder suites: the point is that the build
/// does not need it.
@Suite("Builder: handover")
struct BuilderHandoverTests {
  /// The app's own shape: `DocumentView` builds off the main actor, in an
  /// `@concurrent` function, and awaits the value. A build that quietly came to need the main actor would trap or diverge
  /// here rather than pass.
  @Test(arguments: ["rfc8999.xml", "rfc2119.txt"])
  func aBuildOffTheMainActorMatchesOneOnIt(fixture: String) async throws {
    let document = try Self.document(fixture)
    let style = ReadingStyle()
    let detached = await Task.detached { DocumentTextBuilder.build(document, style: style) }.value
    let onMain = await MainActor.run { DocumentTextBuilder.build(document, style: style) }

    #expect(detached.text.string == onMain.text.string)
    #expect(detached.anchors == onMain.anchors)
    #expect(Self.runs(of: detached.text) == Self.runs(of: onMain.text))
  }

  /// No paragraph style can be mutated once it is in the text. Foundation uniques
  /// equal attribute dictionaries across every string in the process, so two
  /// builds end up holding the same paragraph style objects — measured: 21 of
  /// RFC 8999's 47 were shared with a second build. A shared object is only safe
  /// to read from two threads if nothing can write it, which for a paragraph style
  /// means it must not be an `NSMutableParagraphStyle`.
  @Test(arguments: ["rfc8999.xml", "rfc2119.txt"])
  func noParagraphStyleIsMutable(fixture: String) throws {
    let text = DocumentTextBuilder.build(try Self.document(fixture), style: ReadingStyle()).text
    var mutable = 0
    text.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: text.length)) {
      value, _, _ in
      if value is NSMutableParagraphStyle { mutable += 1 }
    }
    #expect(mutable == 0)
  }

  /// Attachments are mutable, and each build must make its own: a cache that kept
  /// one across builds would share it between a result on the main actor and a
  /// build still running.
  @Test func noAttachmentIsSharedBetweenBuilds() throws {
    let document = try Fixtures.rfc8999()
    // Both held until the comparison: an identity is an address, and a build
    // freed early hands its addresses on to the next one.
    let firstBuild = DocumentTextBuilder.build(document, style: ReadingStyle())
    let secondBuild = DocumentTextBuilder.build(document, style: ReadingStyle())
    let first = Self.attachments(in: firstBuild.text)
    let second = Self.attachments(in: secondBuild.text)

    #expect(!first.isEmpty)
    #expect(first.isDisjoint(with: second))
    withExtendedLifetime((firstBuild, secondBuild)) {}
  }

  /// A kept build is installed again, into another text view, every time it is
  /// reused (#374). `install` copies the text but not the attribute values, so both
  /// storages hold the build's own objects — its chips' attachments by identity.
  /// That is safe while the reuse stays on the main actor and nothing the text
  /// views do writes to the build, which is what this pins: the build reads the
  /// same after two text views have laid it out, at two different columns, and
  /// drawn it — drawing is where AppKit makes an attachment's cell and view.
  @MainActor
  @Test func `a build installed into two text views is left as it was`() throws {
    let built = DocumentTextBuilder.build(try Fixtures.rfc8999(), style: ReadingStyle())
    let runs = Self.runs(of: built.text)
    let string = built.text.string
    let attachments = Self.attachmentStates(in: built.text)
    #expect(!attachments.isEmpty)

    var installed: [String?] = []
    for column in [712.0, 512.0] {
      #if canImport(AppKit)
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.frame = CGRect(x: 0, y: 0, width: column, height: 4_000)
        textView.textContainer?.lineFragmentPadding = 0
        let storage = try #require(textView.textContentStorage)
        let layout = try #require(textView.textLayoutManager)
        storage.install(built.text)
        layout.ensureLayout(for: layout.documentRange)
        let bitmap = try #require(textView.bitmapImageRepForCachingDisplay(in: textView.bounds))
        textView.cacheDisplay(in: textView.bounds, to: bitmap)
      #else
        let storage = NSTextContentStorage()
        let layout = NSTextLayoutManager()
        let container = NSTextContainer(size: CGSize(width: column, height: 1e7))
        container.lineFragmentPadding = 0
        layout.textContainer = container
        storage.addTextLayoutManager(layout)
        storage.install(built.text)
        layout.ensureLayout(for: layout.documentRange)
      #endif
      installed.append(storage.textStorage?.string)
    }

    #expect(installed == [string, string])
    #expect(built.text.string == string)
    #expect(Self.runs(of: built.text) == runs)
    #expect(Self.attachmentStates(in: built.text) == attachments)
  }

  /// What a text view could change about an attachment: its bounds, its image and
  /// its contents, per attachment, in document order.
  private static func attachmentStates(in text: NSAttributedString) -> [String] {
    var states: [String] = []
    text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) {
      value, range, _ in
      guard let attachment = value as? NSTextAttachment else { return }
      let image = attachment.image.map { "\(ObjectIdentifier($0))" } ?? "none"
      states.append(
        "\(range.location) \(attachment.bounds) \(image) \(attachment.contents?.count ?? -1)")
    }
    return states
  }

  private static func document(_ fixture: String) throws -> RFCDocument {
    fixture.hasSuffix(".xml") ? try Fixtures.rfc8999() : try Fixtures.rfc2119()
  }

  /// The attribute runs, as key sets over ranges: enough to tell two builds apart
  /// without comparing attachments, which are equal only to themselves.
  private static func runs(of text: NSAttributedString) -> [String] {
    var runs: [String] = []
    text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) {
      attributes, range, _ in
      let keys = attributes.keys.map(\.rawValue).sorted().joined(separator: ",")
      runs.append("\(range.location)+\(range.length):\(keys)")
    }
    return runs
  }

  private static func attachments(in text: NSAttributedString) -> Set<ObjectIdentifier> {
    var identities: Set<ObjectIdentifier> = []
    text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) {
      value, _, _ in
      if let attachment = value as? NSTextAttachment {
        identities.insert(ObjectIdentifier(attachment))
      }
    }
    return identities
  }
}
