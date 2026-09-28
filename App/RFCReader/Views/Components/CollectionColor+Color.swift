import RFCReaderKit
import SwiftUI

extension CollectionColor {
  /// The system colour a collection's name stands for, adapting to dark mode and
  /// increased contrast.
  var color: Color {
    switch self {
    case .blue: .blue
    case .green: .green
    case .orange: .orange
    case .red: .red
    case .purple: .purple
    case .pink: .pink
    case .teal: .teal
    case .yellow: .yellow
    case .gray: .gray
    }
  }
}
