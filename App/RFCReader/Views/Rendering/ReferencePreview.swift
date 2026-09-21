import RFCKit
import SwiftUI

/// A card previewing a cross reference's target: hover on macOS, long press on
/// iOS. Reads the target from the library's index rather than the reference's
/// own text, which is deliberately terse ("Section 4.2 of [RFC9110]").
struct ReferencePreview: View {
    let reference: CrossReference
    let library: LibraryModel

    private var documentID: DocumentID? {
        guard case .document(let id, _) = reference.target else { return nil }
        return id
    }

    private var section: String? {
        guard case .document(_, let section) = reference.target else { return nil }
        return section
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
                Button("Open \(metadata.id.displayName)") {
                    library.open(metadata.id, section: section)
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
