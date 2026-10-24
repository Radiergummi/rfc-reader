import CoreGraphics
import Foundation
import RFCKit

/// How much of the document an export or a print takes (#386): all of it, or the
/// section the reader is in, with its subsections.
public enum ExportScope: String, CaseIterable, Identifiable, Sendable {
  case wholeDocument
  case currentSection

  public var id: String { rawValue }

  /// What the save and print panels' pop-up calls it. In title case, as a menu's
  /// item is, where the errata summary's "Whole document" is a sentence's.
  public func name(in locale: Locale = .interface) -> String {
    switch self {
    case .wholeDocument: String(kit: "Whole Document", locale: locale)
    case .currentSection: String(kit: "Current Section", locale: locale)
    }
  }

  /// The section to export in this scope and `format`: `current`, the anchor of
  /// the section on screen, when this is the current section and the format takes
  /// one; nil for the whole document.
  public func section(_ current: String?, for format: ExportFormat) -> String? {
    self == .currentSection && format.narrows ? current : nil
  }
}

/// What an export is made of (#386): the whole document, or one section of it and
/// the document a link to the rest goes to.
public struct ExportedPart: Sendable {
  public let document: RFCDocument
  /// The document the part was narrowed out of; nil for a whole document.
  public let outside: DocumentID?

  /// The section the anchor `section` names narrowed out of `whole`, or `whole`
  /// when `section` is nil. A section the document no longer has is an error, never
  /// the whole document under the section's name.
  public init(of whole: RFCDocument, section: String?) throws {
    guard let section else {
      self.document = whole
      self.outside = nil
      return
    }
    guard let narrowed = whole.narrowed(toSection: section) else { throw SectionMissing() }
    self.document = narrowed
    self.outside = whole.header.id
  }

  /// A section to export that the document does not have.
  public struct SectionMissing: LocalizedError {
    public var errorDescription: String? {
      String(kit: "The section is no longer in the document.", locale: .interface)
    }
  }
}

extension ExportFormat {
  /// Whether this format can take one section: a format made from the document.
  /// A published file is the whole file, and a grammar and the highlights and notes
  /// are the whole document's.
  public var narrows: Bool {
    switch self {
    case .pdf, .epub, .html, .markdown: true
    case .text, .xml, .abnf, .annotations: false
    }
  }

  /// `RFC-10042.pdf`, `BCP-14.pdf`: the document's file, named as it is cited.
  /// `RFC-9110-section-4.2.pdf`, `RFC-9110-introduction.pdf`: the file of one
  /// section, named as the document's is, then by the section's anchor, which an
  /// RFC's links name it by too. An anchor is an XML name, so it is a file's too.
  /// `RFC-9110 Highlights and Notes.md`: the highlights and notes, which are not
  /// the document's Markdown and must not take its name.
  public func fileName(
    for id: DocumentID, section anchor: String? = nil, locale: Locale = .interface
  ) -> String {
    "\(fileStem(for: id, section: anchor, locale: locale)).\(pathExtension)"
  }

  /// `RFC-9110-section-4.2`: the file name without its extension, which iOS's Save
  /// to Files adds; the document's for no section.
  public func fileStem(
    for id: DocumentID, section anchor: String? = nil, locale: Locale = .interface
  ) -> String {
    let document = Self.fileStem(for: id)
    if self == .annotations {
      return String(kit: "\(document) Highlights and Notes", locale: locale)
    }
    return anchor.map { "\(document)-\($0)" } ?? document
  }
}

/// Where the pages of a laid-out PDF go when it is printed through a view of its
/// own (#386): one paper's height each, the first at the top, and each page's
/// content fitted to the paper chosen, as PDFKit's own print fits it.
public enum PrintedPages {
  /// The view's frame for `count` pages of `paper`.
  public static func size(count: Int, paper: CGSize) -> CGSize {
    CGSize(width: paper.width, height: paper.height * CGFloat(max(count, 1)))
  }

  /// Page `page`'s rect, counting from 1, in a view that is not flipped.
  public static func rect(forPage page: Int, count: Int, paper: CGSize) -> CGRect {
    CGRect(
      x: 0, y: CGFloat(count - page) * paper.height, width: paper.width, height: paper.height)
  }

  /// `bounds` scaled to fit `rect`, keeping its proportions, and centered in it.
  public static func fitted(_ bounds: CGSize, in rect: CGRect) -> CGRect {
    guard bounds.width > 0, bounds.height > 0 else { return rect }
    let scale = min(rect.width / bounds.width, rect.height / bounds.height)
    let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    return CGRect(
      x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width,
      height: size.height)
  }
}
