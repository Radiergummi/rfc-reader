import RFCKit

/// What a converted legacy document's header takes from the RFC index rather than from
/// its title page.
///
/// The index is the RFC Editor's own record, and a title page states these facts less
/// reliably than anything else in the document: RFC 5's date is `June 2, l969`, with a
/// lower-case L for the 1, RFC 822's author and date come out empty, and RFC 1483
/// spells its label `Reguest for Comments`, so no number is recognised at all (#218,
/// #203). The title takes its own path, through `LegacyTextParser.parse(_:title:)`,
/// because parsing needs it to filter the lead-in; nothing here is used while parsing.
public enum IndexHeader {
  /// Applies `entry` to `header`: its number, its authors with their order and roles,
  /// its year and month, and what the document obsoletes and updates.
  ///
  /// The day is the index's where it has one, which is only for the April 1
  /// documents. Otherwise the page's day is kept, but only where the page's year and
  /// month are the index's: a day from another month belongs to a date the index has
  /// already corrected.
  ///
  /// Returns notes for the report. A page that states no number, or another number
  /// than the index's, is worth knowing about even once the number is right.
  public static func apply(_ entry: RFCMetadata, to header: inout DocumentHeader) -> [String] {
    var notes: [String] = []
    if header.id != entry.id {
      let stated = header.id.map { "states \($0.number)" } ?? "states none"
      notes.append("RFC number from the index; the front matter \(stated)")
    }
    header.id = entry.id
    header.authors = entry.authors

    var date = PublicationDate(year: entry.date.year, month: entry.date.month)
    if let day = entry.date.day {
      date.day = day
    } else if let page = header.date, page.year == date.year, page.month == date.month {
      date.day = page.day
    }
    header.date = date

    header.obsoletes = entry.obsoletes
    header.updates = entry.updates
    return notes
  }
}
