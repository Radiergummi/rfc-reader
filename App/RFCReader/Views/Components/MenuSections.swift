import RFCReaderKit
import SwiftUI

/// A `DocumentMenus` menu as SwiftUI items: a toggle for an item that is on or off,
/// a button otherwise, and a divider between sections — which is a separator in a
/// menu and a rule in a list, where Add to Collection is shown as a sheet.
struct MenuSections<Performed: Hashable & Sendable>: View {
  let sections: DocumentMenus.Sections<Performed>
  let perform: (Performed) -> Void

  var body: some View {
    ForEach(Array(sections.enumerated()), id: \.offset) { index, items in
      if index > 0 { Divider() }
      ForEach(items, id: \.self) { item in
        if let isOn = item.isOn {
          Toggle(isOn: Binding(get: { isOn }, set: { _ in perform(item.action) })) {
            label(for: item)
          }
        } else {
          Button {
            perform(item.action)
          } label: {
            label(for: item)
          }
        }
      }
    }
  }

  @ViewBuilder private func label(for item: DocumentMenus.Item<Performed>) -> some View {
    if let icon = item.icon?.label {
      // macOS 27 hides a menu item's icon unless the label asks to keep it.
      Label {
        Text(item.title)
      } icon: {
        icon
      }
      .labelStyle(.titleAndIcon)
    } else {
      Text(item.title)
    }
  }
}
