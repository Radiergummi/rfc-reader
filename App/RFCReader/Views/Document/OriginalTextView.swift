import SwiftUI

struct OriginalTextView: View {
  let text: String?
  let fontSize: Double

  var body: some View {
    if let text {
      #if os(macOS)
        OriginalTextBody(text: text, fontSize: fontSize)
      #else
        // Still a `Text` on iOS: a `UITextView` keeps its content as wide as its
        // frame, so the unwrapped 72-column lines would be clipped with no way to
        // scroll to them, where this scroll view pans both ways.
        ScrollView([.vertical, .horizontal]) {
          Text(text)
            .font(.system(size: fontSize * 0.85, design: .monospaced))
            .textSelection(.enabled)
            .padding(24)
        }
      #endif
    } else {
      ProgressView()
    }
  }
}
