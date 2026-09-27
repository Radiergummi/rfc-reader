import Contacts
import ContactsUI
import RFCKit
import RFCReaderKit
import SwiftUI

/// The header's authors as people rather than a caption (#19): each one a monogram
/// and a name, wrapping onto as many lines as it takes. An author whose document
/// publishes contact details opens a contact card; one whose does not — every legacy
/// header, every author the index names — is the same chip, but not a button.
struct AuthorChips: View {
  let authors: [Author]

  var body: some View {
    WrappingRowLayout(spacing: 6) {
      ForEach(Array(authors.enumerated()), id: \.offset) { _, author in
        AuthorChip(author: author)
      }
    }
  }
}

private struct AuthorChip: View {
  let author: Author
  @State private var showsCard = false

  var body: some View {
    if AuthorCard.hasCard(author) {
      Button {
        showsCard = true
      } label: {
        label
      }
      .buttonStyle(.plain)
      .help("Show contact details")
      .popover(isPresented: $showsCard) {
        ContactCard(contact: AuthorCard.contact(for: author))
          .frame(minWidth: 320, idealWidth: 340, minHeight: 480, idealHeight: 540)
      }
    } else {
      label
    }
  }

  private var label: some View {
    HStack(spacing: 5) {
      Monogram(name: author.name)
      Text(author.role == nil ? author.name : "\(author.name), Ed.")
        .lineLimit(1)
    }
    .padding(.vertical, 2)
    .padding(.leading, 2)
    .padding(.trailing, 8)
    .background(.quaternary.opacity(0.5), in: .capsule)
    .accessibilityElement(children: .combine)
  }
}

/// Two initials on a tint of their own, the way Contacts draws a person with no
/// photo. The colours are `AuthorMonogram`'s, which hold the initials to 4.5:1
/// against every tint. The fill is flat rather than the system `gradient`, which
/// would lighten part of the circle away from the value that was measured.
private struct Monogram: View {
  let name: String
  @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 20

  var body: some View {
    Text(AuthorMonogram.initials(for: name))
      .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
      .foregroundStyle(Color(AuthorMonogram.initialsColour))
      .frame(width: size, height: size)
      .background(Color(AuthorMonogram.tintColour(for: name)), in: .circle)
      .accessibilityHidden(true)
  }
}

extension Color {
  /// A colour whose contrast RFCReaderKit has measured, drawn as exactly those sRGB
  /// values in every appearance.
  fileprivate init(_ colour: SRGBColour) {
    self.init(.sRGB, red: colour.red, green: colour.green, blue: colour.blue)
  }
}

/// Lays its children out left to right, starting a new line wherever the next one
/// would not fit; where each lands is `WrappingRow`'s. The cache holds each child's
/// own size, which does not depend on the width, so a layout pass measures a child
/// again only when it is wider than the line.
private struct WrappingRowLayout: Layout {
  let spacing: CGFloat

  func makeCache(subviews: Subviews) -> [CGSize] {
    subviews.map { $0.sizeThatFits(.unspecified) }
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize])
    -> CGSize
  {
    WrappingRow.size(of: frames(subviews, width: proposal.width ?? .infinity, cache: cache))
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize]
  ) {
    for (subview, frame) in zip(subviews, frames(subviews, width: bounds.width, cache: cache)) {
      subview.place(
        at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
        proposal: ProposedViewSize(frame.size))
    }
  }

  /// Each child at its own width, or the line's when it is wider: a chip is never
  /// wider than the column, and its name truncates instead.
  private func frames(_ subviews: Subviews, width: CGFloat, cache: [CGSize]) -> [CGRect] {
    let sizes = zip(subviews, cache).map { subview, ideal in
      ideal.width > width
        ? subview.sizeThatFits(ProposedViewSize(width: width, height: nil)) : ideal
    }
    return WrappingRow.frames(for: sizes, width: width, spacing: spacing)
  }
}

/// Apple's own card for a contact that is not in the address book: the native
/// layout, working email and phone links, and Add to Contacts.
#if os(macOS)
  private struct ContactCard: NSViewControllerRepresentable {
    let contact: CNMutableContact

    func makeNSViewController(context: Context) -> CNContactViewController {
      let card = CNContactViewController()
      card.contact = contact
      return card
    }

    func updateNSViewController(_ card: CNContactViewController, context: Context) {}
  }
#else
  private struct ContactCard: UIViewControllerRepresentable {
    let contact: CNMutableContact

    /// In a navigation controller, which is where the card's own actions — Create
    /// New Contact, Add to Existing Contact — push their screens.
    func makeUIViewController(context: Context) -> UINavigationController {
      let card = CNContactViewController(forUnknownContact: contact)
      card.allowsEditing = false
      // Without a store the card hides its own add actions.
      card.contactStore = CNContactStore()
      return UINavigationController(rootViewController: card)
    }

    func updateUIViewController(_ navigation: UINavigationController, context: Context) {}
  }
#endif
