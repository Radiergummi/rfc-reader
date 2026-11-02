import RFCKit
import SwiftUI

/// Go to Section… (⌥⌘G, #711): a field that takes a section number or appendix
/// letter, `4.2` or `A.1`, as a heading shows it, and goes there. A number the
/// document does not have shakes the field and says so; the field stays for another.
struct GoToSectionField: View {
  /// The document's sections, which a number is looked up among.
  let sections: [RFCKit.Section]
  /// Goes to the section with this anchor, as a row of the contents does.
  let goTo: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var typed = ""
  /// What was typed last that names no section, while it is what the field holds.
  @State private var notFound: String?
  /// How many times a number was not found: each one shakes the field.
  @State private var misses = 0
  @FocusState private var isFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      TextField("Section", text: $typed, prompt: Text("Section number, such as 4.2"))
        .textFieldStyle(.roundedBorder)
        .autocorrectionDisabled()
        #if !os(macOS)
          .textInputAutocapitalization(.characters)
          .keyboardType(.numbersAndPunctuation)
        #endif
        .focused($isFocused)
        .onSubmit(submit)
        .keyframeAnimator(initialValue: 0.0, trigger: misses) { [reduceMotion] field, offset in
          field.offset(x: reduceMotion ? 0 : offset)
        } keyframes: { _ in
          LinearKeyframe(-8.0, duration: 0.05)
          LinearKeyframe(8.0, duration: 0.05)
          LinearKeyframe(-6.0, duration: 0.05)
          LinearKeyframe(6.0, duration: 0.05)
          LinearKeyframe(0.0, duration: 0.05)
        }
      if let notFound, notFound == typed {
        Text("This document has no section \(notFound).")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding()
    .frame(width: 260)
    .onAppear { isFocused = true }
  }

  private func submit() {
    guard let anchor = SectionInput.anchor(typed, in: sections) else {
      notFound = typed
      misses += 1
      AccessibilityNotification.Announcement(
        String(localized: "This document has no section \(typed).")
      ).post()
      return
    }
    goTo(anchor)
    dismiss()
  }
}
