import CoreGraphics
import Foundation
import RFCKit

/// How much of the document an export or a print takes (#386): all of it, or the
/// section the reader is in, with its subsections.
public enum ExportScope: String, CaseIterable, Identifiable, Sendable {
  case wholeDocument
  case currentSection

  public var id: String { rawValue }

  /// What the save and print panels' pop-up calls it.
  public func name(in locale: Locale = .interface) -> String {
    switch self {
    case .wholeDocument: String(kit: "Whole Document", locale: locale)
    case .currentSection: String(kit: "Current Section", locale: locale)
    }
  }

  /// What `document` becomes for this scope: itself, or the section `section`
  /// names narrowed out of it. Nil when there is no such section.
  public func document(_ document: RFCDocument, section: String?) -> RFCDocument? {
    switch self {
    case .wholeDocument: document
    case .currentSection: section.flatMap { document.narrowed(toSection: $0) }
    }
  }
}

extension ExportFormat {
  /// Whether this format can take one section: a format made from the document.
  /// A published file is the whole file, and a grammar is the whole document's.
  public var narrows: Bool {
    switch self {
    case .pdf, .epub, .html, .markdown: true
    case .text, .xml, .abnf: false
    }
  }

  /// `RFC-9110-section-4.2.pdf`, `RFC-9110-introduction.pdf`: the file of one
  /// section, named as the document's is, then by the section's anchor, which an
  /// RFC's links name it by too. An anchor is an XML name, so it is a file's too.
  public func fileName(for id: DocumentID, section anchor: String) -> String {
    "\(Self.fileStem(for: id, section: anchor)).\(pathExtension)"
  }

  /// `RFC-9110-section-4.2`: a section's file name without its extension, which
  /// iOS's Save to Files adds; the document's for no section.
  public static func fileStem(for id: DocumentID, section anchor: String?) -> String {
    anchor.map { "\(fileStem(for: id))-\($0)" } ?? fileStem(for: id)
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
