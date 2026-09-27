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
    WrappingRow(spacing: 6) {
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
/// photo.
private struct Monogram: View {
  let name: String
  @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 20

  private static let palette: [Color] = [
    .red, .orange, .yellow, .green, .mint, .teal, .blue, .indigo,
  ]

  var body: some View {
    Text(AuthorMonogram.initials(for: name))
      .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(
        Self.palette[AuthorMonogram.tint(for: name, among: Self.palette.count)].gradient,
        in: .circle
      )
      .accessibilityHidden(true)
  }
}

/// Lays its children out left to right, starting a new line wherever the next one
/// would not fit.
private struct WrappingRow: Layout {
  let spacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = arrange(subviews, width: proposal.width ?? .infinity)
    let width = rows.map(\.width).max() ?? 0
    let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
    return CGSize(width: width, height: height)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    var y = bounds.minY
    for row in arrange(subviews, width: bounds.width) {
      var x = bounds.minX
      for index in row.indices {
        let size = Self.size(of: subviews[index], within: bounds.width)
        subviews[index].place(
          at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
          proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
      y += row.height + spacing
    }
  }

  /// Its own width, or the row's when it is wider: a chip is never wider than the
  /// column, and its name truncates instead.
  private static func size(of subview: LayoutSubview, within width: CGFloat) -> CGSize {
    let ideal = subview.sizeThatFits(.unspecified)
    guard ideal.width > width else { return ideal }
    return subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
  }

  private struct Row {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
    var rows: [Row] = []
    var row = Row()
    for index in subviews.indices {
      let size = Self.size(of: subviews[index], within: width)
      let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
      if needed > width, !row.indices.isEmpty {
        rows.append(row)
        row = Row()
      }
      row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
      row.height = max(row.height, size.height)
      row.indices.append(index)
    }
    if !row.indices.isEmpty { rows.append(row) }
    return rows
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
