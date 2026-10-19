import Foundation

/// The words the builder writes into the body itself, rather than taking from the
/// document: the abstract's heading, an aside's caption, a figure's and a table's,
/// an appendix's number, a heading's backlink caption.
///
/// English, as the body is (decision "The app's chrome is localized, the reader body
/// is not"), except in a translated document (#749), where English labels beside
/// translated prose would be the mixed-language body that decision rejects. Those
/// are translated by the same session as the prose, from `sources`.
public struct DocumentLabels: Sendable, Hashable {
  public var abstract = "Abstract"
  public var note = "Note"
  public var notes = "Notes"
  public var figure = "Figure"
  public var table = "Table"
  public var appendix = "Appendix"
  public var annex = "Annex"
  public var oneBacklink = "One Backlink"
  public var twoBacklinks = "Two Backlinks"
  public var threeBacklinks = "Three Backlinks"
  /// After a count of four or more.
  public var backlinks = "Backlinks"

  public static let english = DocumentLabels()

  /// What a translation of the labels is asked to translate. A label that names a
  /// numbered thing is asked for with a number, "Figure 1", so it is translated as
  /// a label and not as a word on its own ("Table" is also a piece of furniture);
  /// the label is what the translation says beside the number.
  public static let sources = [
    "Abstract", "Note", "Notes", "One Backlink", "Two Backlinks", "Three Backlinks",
    "Figure 1", "Table 1", "Appendix A", "Annex A", "4 Backlinks",
  ]

  public init() {}

  /// The labels `translations` give for `sources`. Where one is missing, or a
  /// numbered phrase lost its number, so that which of its words is the label
  /// cannot be told, the label stays English.
  public init(translating translations: [String: String]) {
    func word(_ source: String) -> String? {
      translations[source].flatMap { $0.isEmpty ? nil : $0 }
    }
    // The label is what is left of the phrase without its number, where the number
    // is on the side the builder sets it: after "Abbildung" and "図", before
    // "Rückverweise". A language that puts it on the other side, "1. ábra", keeps the
    // English.
    func label(_ source: String, beside number: String, numberFirst: Bool = false) -> String? {
      guard let translated = translations[source],
        numberFirst ? translated.hasPrefix(number) : translated.hasSuffix(number)
      else { return nil }
      let rest =
        numberFirst ? translated.dropFirst(number.count) : translated.dropLast(number.count)
      let label = rest.trimmingCharacters(in: .whitespaces)
      // A letter, an appendix's, is only the number where it stands apart from the
      // word: the "A" of "Anhang A", not of "MANA".
      let isApart = label.count < rest.count || number.allSatisfy(\.isNumber)
      guard !label.isEmpty, isApart else { return nil }
      return label
    }
    abstract = word("Abstract") ?? abstract
    note = word("Note") ?? note
    notes = word("Notes") ?? notes
    oneBacklink = word("One Backlink") ?? oneBacklink
    twoBacklinks = word("Two Backlinks") ?? twoBacklinks
    threeBacklinks = word("Three Backlinks") ?? threeBacklinks
    figure = label("Figure 1", beside: "1") ?? figure
    table = label("Table 1", beside: "1") ?? table
    appendix = label("Appendix A", beside: "A") ?? appendix
    annex = label("Annex A", beside: "A") ?? annex
    backlinks = label("4 Backlinks", beside: "4", numberFirst: true) ?? backlinks
  }

  /// What a backlink caption says, and VoiceOver says for it: the number of
  /// sections that refer to the section — not of references, of which one section
  /// may make several — in words up to three.
  public func backlinksCaption(count: Int) -> String {
    switch count {
    case 1: oneBacklink
    case 2: twoBacklinks
    case 3: threeBacklinks
    default: "\(count) \(backlinks)"
    }
  }
}
