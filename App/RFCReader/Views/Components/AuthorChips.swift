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
      .background {
        ContactCardPresenter(isPresented: $showsCard, author: author)
      }
    } else {
      label
    }
  }

  private var label: some View {
    HStack(spacing: 5) {
      Monogram(name: author.name)
      Text(author.displayName)
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
/// photo. The colors are `AuthorMonogram`'s, which hold the initials to 4.5:1
/// against every tint. The fill is flat rather than the system `gradient`, which
/// would lighten part of the circle away from the value that was measured.
private struct Monogram: View {
  let name: String
  @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 20

  var body: some View {
    Text(AuthorMonogram.initials(for: name))
      .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
      .foregroundStyle(Color(AuthorMonogram.initialsColor))
      .frame(width: size, height: size)
      .background(Color(AuthorMonogram.tintColor(for: name)), in: .circle)
      .accessibilityHidden(true)
  }
}

extension Color {
  /// A color whose contrast RFCReaderKit has measured, drawn as exactly those sRGB
  /// values in every appearance.
  fileprivate init(_ color: SRGBColor) {
    self.init(.sRGB, red: color.red, green: color.green, blue: color.blue)
  }
}

/// Apple's own card for a contact that is not in the address book: the native
/// layout, working email and phone links, and Add to Contacts.
#if os(macOS)
  /// Presents the card in an `NSPopover` rather than SwiftUI's, whose arrow is
  /// drawn in the popover's material while the card paints its own poster beneath
  /// it: a gray tip on a colored card. `hasFullSizeContent` lets the card reach
  /// into the arrow, the way Contacts' own popovers look.
  private struct ContactCardPresenter: NSViewRepresentable {
    @Binding var isPresented: Bool
    let author: Author

    func makeNSView(context: Context) -> NSView {
      NSView()
    }

    func updateNSView(_ anchor: NSView, context: Context) {
      context.coordinator.isPresented = $isPresented
      guard isPresented, context.coordinator.popover == nil else { return }

      let card = CNContactViewController()
      card.contact = AuthorCard.contact(for: author)

      let popover = NSPopover()
      popover.contentViewController = card
      popover.contentSize = NSSize(width: 340, height: 540)
      popover.behavior = .transient
      popover.hasFullSizeContent = true
      popover.delegate = context.coordinator
      context.coordinator.popover = popover
      popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }

    static func dismantleNSView(_ anchor: NSView, coordinator: Coordinator) {
      coordinator.popover?.close()
    }

    func makeCoordinator() -> Coordinator {
      Coordinator(isPresented: $isPresented)
    }

    /// Hears the popover close, so the chip can open the card again.
    final class Coordinator: NSObject, NSPopoverDelegate {
      var isPresented: Binding<Bool>
      var popover: NSPopover?

      init(isPresented: Binding<Bool>) {
        self.isPresented = isPresented
      }

      func popoverDidClose(_ notification: Notification) {
        popover = nil
        isPresented.wrappedValue = false
      }
    }
  }
#else
  /// Presents the card from UIKit: a popover on an iPad, a sheet on an iPhone.
  ///
  /// On an iPhone the sheet cannot be swiped away by its card. Contacts draws the
  /// card in its own process, and every touch on it goes there: none of this
  /// process's gesture recognizers sees one, the sheet's pan included, and the
  /// card reaches over the sheet's grabber. That is so however the card is
  /// presented — SwiftUI popover, UIKit popover, page sheet — and Notes does the
  /// same on iOS 27. Without its navigation controller the card does not appear.
  /// Hence the Close button.
  private struct ContactCardPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let author: Author

    func makeUIViewController(context: Context) -> UIViewController {
      UIViewController()
    }

    func updateUIViewController(_ anchor: UIViewController, context: Context) {
      context.coordinator.isPresented = $isPresented
      guard isPresented, anchor.presentedViewController == nil else { return }

      let card = CNContactViewController(forUnknownContact: AuthorCard.contact(for: author))
      card.allowsEditing = false
      // Without a store the card hides its own add actions.
      card.contactStore = CNContactStore()
      // A card for an unknown contact has no Done button of its own.
      card.navigationItem.rightBarButtonItem = UIBarButtonItem(
        systemItem: .close,
        primaryAction: UIAction { [weak anchor] _ in
          anchor?.dismiss(animated: true)
          isPresented = false
        })

      // In a navigation controller, which is where the card's own actions — Create
      // New Contact, Add to Existing Contact — push their screens.
      let navigation = UINavigationController(rootViewController: card)
      navigation.modalPresentationStyle = .popover
      navigation.preferredContentSize = CGSize(width: 340, height: 540)
      navigation.popoverPresentationController?.sourceView = anchor.view
      navigation.delegate = context.coordinator
      navigation.presentationController?.delegate = context.coordinator
      anchor.present(navigation, animated: true)
    }

    func makeCoordinator() -> Coordinator {
      Coordinator(isPresented: $isPresented)
    }

    /// Hears a swipe or a tap outside end the presentation, so the chip can open
    /// the card again, and dresses the navigation bar for the screen beneath it.
    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate,
      UINavigationControllerDelegate
    {
      var isPresented: Binding<Bool>

      init(isPresented: Binding<Bool>) {
        self.isPresented = isPresented
      }

      func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        isPresented.wrappedValue = false
      }

      /// The card draws its poster in dark style, but only inside its own view; the
      /// bar is the navigation controller's, and left alone its Close button is
      /// light glass with a dark glyph over the poster, where Apple's is clear with
      /// a white one. The screens the card pushes have ordinary backgrounds, so the
      /// bar goes back to the app's own style for them.
      func navigationController(
        _ navigationController: UINavigationController, willShow viewController: UIViewController,
        animated: Bool
      ) {
        navigationController.navigationBar.overrideUserInterfaceStyle =
          viewController is CNContactViewController ? .dark : .unspecified
      }
    }
  }
#endif
