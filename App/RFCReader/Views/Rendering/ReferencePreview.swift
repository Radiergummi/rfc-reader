import RFCKit
import SwiftUI

/// A card previewing a cross reference's target: hover on macOS, long press on
/// iOS. Reads the target from the library's index rather than the reference's
/// own text, which is deliberately terse ("Section 4.2 of [RFC9110]"). Purely
/// informational — no button: on macOS the popover closes on `mouseExited` the
/// moment the pointer moves toward it, so a button inside could never be
/// clicked, and on iOS the same view is a non-interactive context-menu preview.
/// Clicking the chip itself already opens the document, through `clickedOnLink`
/// on macOS and `primaryActionFor` on iOS.
struct ReferencePreview: View {
    let reference: CrossReference
    let library: LibraryModel

    private var documentID: DocumentID? {
        guard case .document(let id, _) = reference.target else { return nil }
        return id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let metadata = documentID.flatMap(library.metadata) {
                HStack(alignment: .firstTextBaseline) {
                    Text(metadata.title).font(.headline).lineLimit(2)
                    Spacer()
                    StatusBadge(status: metadata.currentStatus)
                }
                if let abstract = metadata.abstract {
                    Text(abstract).font(.callout).foregroundStyle(.secondary).lineLimit(4)
                }
            } else if let documentID {
                // Referenced but not in the library's index — an unpublished draft,
                // or a corpus gap. Never a blank card: name what we do know.
                Text(documentID.displayName).font(.headline)
                Text("Not available in the library.").font(.callout).foregroundStyle(.secondary)
            } else {
                // An in-document anchor, or a reference with no resolvable target.
                Text(reference.text ?? "Reference").font(.headline)
            }
        }
        .padding(12)
        .frame(width: 280, alignment: .leading)
    }
}
