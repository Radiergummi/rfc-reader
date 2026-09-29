import RFCReaderKit
import SwiftUI

/// A `DocumentMenus` menu as SwiftUI items: a toggle for an item that is on or off,
/// a button otherwise, and a divider between sections — which is a separator in a
/// menu and a rule in a list, where Add to Collection is shown as a sheet.
struct MenuSections: View {
  let sections: DocumentMenus.Sections
  let perform: (DocumentMenus.Action) -> Void

  var body: some View {
    ForEach(Array(sections.enumerated()), id: \.offset) { index, items in
      if index > 0 { Divider() }
      ForEach(items, id: \.self) { item in
        if let isOn = item.isOn {
          Toggle(item.title, isOn: Binding(get: { isOn }, set: { _ in perform(item.action) }))
        } else {
          Button(item.title) { perform(item.action) }
        }
      }
    }
  }
}
