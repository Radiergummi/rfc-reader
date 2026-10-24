import RFCReaderKit
import SwiftUI

/// What a working group is, above its RFCs (#363): its name, kind, area and state,
/// its chairs, how much it has published and when, and its pages. The words are
/// `WorkingGroupSummary`'s; this is only their layout.
struct WorkingGroupCard: View {
  /// The group's acronym as the index spells it, which the card follows (#731).
  let group: String
  let summary: WorkingGroupSummary

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text(summary.title)
            .font(.title2.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
          if let acronym = summary.acronym {
            Text(acronym)
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
        FollowGroupButton(group: group)
          // Its own tap target in the list's row, as the links below are.
          .buttonStyle(.bordered)
          .controlSize(.small)
      }
      if !summary.facts.isEmpty {
        Text(summary.facts.joined(separator: " · "))
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      if !summary.chairs.isEmpty {
        Text("Chairs: \(summary.chairs.formatted(.list(type: .and)))")
          .font(.subheadline)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let publications = summary.publications {
        Text(publications)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      if !summary.links.isEmpty {
        WrappingRowLayout(spacing: 14) {
          ForEach(summary.links, id: \.self) { link in
            Link(destination: link.url) {
              Label(link.title, systemImage: link.symbol)
            }
            // Borderless, so each link is its own tap target in the list's row, as
            // the index status's Retry is: a row of plain ones fires them all on iOS.
            .buttonStyle(.borderless)
            .font(.subheadline)
          }
        }
        .padding(.top, 2)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    #if os(macOS)
      // A card of its own on the Mac's inset list; on iOS the grouped list's row is one.
      .padding(12)
      .background(.fill.quaternary, in: .rect(cornerRadius: 10))
    #endif
  }
}

/// Follow Working Group, or Unfollow Working Group for one followed (#731): in a
/// working group's row's context menu and on its card. Nothing for the index's
/// "NON WORKING GROUP", which is not a group.
struct FollowGroupButton: View {
  @Environment(LibraryModel.self) private var library
  let group: String

  var body: some View {
    if WorkingGroupFollowing.canFollow(group) {
      let isFollowed = library.isFollowed(group)
      Button {
        library.toggleFollowed(group)
      } label: {
        Label(
          WorkingGroupFollowing.command(isFollowed: isFollowed),
          systemImage: WorkingGroupFollowing.symbol(isFollowed: isFollowed))
      }
    }
  }
}
