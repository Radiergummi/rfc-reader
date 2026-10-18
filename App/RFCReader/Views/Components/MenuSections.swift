import RFCReaderKit
import SwiftUI

/// A `DocumentMenus` menu as SwiftUI items: a toggle for an item that is on or off,
/// a button otherwise, and a divider between sections — which is a separator in a
/// menu and a rule in a list, where Add to Collection is shown as a sheet.
struct MenuSections<Performed: Hashable & Sendable>: View {
  let sections: DocumentMenus.Sections<Performed>
  /// The menu bar's key equivalents, by what an item does (#761).
  var shortcuts: [Performed: KeyboardShortcut] = [:]
  let perform: (Performed) -> Void

  var body: some View {
    DividedSections(sections: sections) { item in
      if let isOn = item.isOn {
        Toggle(isOn: Binding(get: { isOn }, set: { _ in perform(item.action) })) {
          label(for: item)
        }
        .keyboardShortcut(shortcuts[item.action])
      } else {
        Button {
          perform(item.action)
        } label: {
          label(for: item)
        }
        .keyboardShortcut(shortcuts[item.action])
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

/// Sections of menu items, a divider between each two: one rendering for every
/// `DocumentMenus` table (#761), each item made by `item`.
struct DividedSections<Element: Hashable, Item: View>: View {
  let sections: [[Element]]
  @ViewBuilder let item: (Element) -> Item

  var body: some View {
    ForEach(Array(sections.enumerated()), id: \.offset) { index, elements in
      if index > 0 { Divider() }
      ForEach(elements, id: \.self) { element in
        item(element)
      }
    }
  }
}
