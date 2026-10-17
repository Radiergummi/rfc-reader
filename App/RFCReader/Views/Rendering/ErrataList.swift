import RFCReaderKit
import SwiftUI

/// What an errata chip lists (#387): each erratum of the section, or of the whole
/// document, with its status, type and place, and the original and corrected text, as
/// the Info pane lists them. In a popover on macOS, and a sheet on iOS.
struct ErrataList: View {
  let items: [ErrataSummary.Item]

  /// The list's fixed width in a popover: the reference card's.
  static let width = ReferencePreview.width
  /// The tallest it is before it scrolls: an erratum's texts can be long.
  static let maximumHeight: CGFloat = 420

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        ForEach(items) { item in
          ErratumView(item: item)
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
