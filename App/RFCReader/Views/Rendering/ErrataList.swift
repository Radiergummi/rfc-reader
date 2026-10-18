import RFCReaderKit
import SwiftUI

/// What an errata chip lists (#387): each erratum of the section, or of the whole
/// document, with its status, type and place, and the original and corrected text, as
/// the Info pane lists them. In a popover on macOS, and a sheet on iOS.
struct ErrataList: View {
  let items: [ErrataSummary.Item]
  /// Sized for a popover, at the reference card's width and no taller than its
  /// errata up to a cap; a sheet's fills the sheet.
  var isInPopover = true

  /// The list's fixed width in a popover: the reference card's.
  static let width = ReferencePreview.width
  /// The tallest it is before it scrolls: an erratum's texts can be long.
  static let maximumHeight: CGFloat = 420

  var body: some View {
    let list = ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        ForEach(items) { item in
          ErratumView(item: item)
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    if isInPopover {
      // As tall as the errata up to the cap, not as tall as it is offered, as
      // `BacklinksList` is.
      list
        .frame(maxHeight: Self.maximumHeight)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: Self.width, alignment: .leading)
    } else {
      list
    }
  }
}

/// A request for the whole document's errata, from the reader header on iOS.
struct ErrataRequest: Identifiable {
  let id = UUID()
  let items: [ErrataSummary.Item]
}

#if os(iOS)
  /// `ErrataList` in a sheet of its own, with a title and a Done button: on iOS, where
  /// the texts are long for a popover.
  struct ErrataSheet: View {
    let items: [ErrataSummary.Item]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
      NavigationStack {
        ErrataList(items: items, isInPopover: false)
          .navigationTitle("Errata")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") { dismiss() }
            }
          }
      }
      .presentationDetents([.medium, .large])
    }
  }
#endif
