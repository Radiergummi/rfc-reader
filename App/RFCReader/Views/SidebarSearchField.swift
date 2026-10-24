import RFCKit
import RFCReaderKit
import SwiftUI

#if os(macOS)
  /// The sidebar's search field: AppKit's own `NSSearchField`, so it draws, clears and
  /// behaves as every other Mac search field does (#157).
  ///
  /// Takes the model rather than a binding out of `SidebarView.body`: a binding made
  /// up there makes the whole sidebar — the filter list, the working groups, the index
  /// status — depend on the search text and re-evaluate on every keystroke. In here
  /// the dependency reaches no further than the field.
  struct SidebarSearchField: NSViewRepresentable {
    let navigation: NavigationModel
    /// Where completion finds the working groups to offer.
    let library: LibraryModel

    func makeNSView(context: Context) -> NSSearchField {
      let field = NSSearchField()
      // Just "Search…": the syntax is taught by the filters the field suggests (#781).
      field.placeholderString = String(localized: "Search…")
      field.delegate = context.coordinator
      field.suggestionsDelegate = context.coordinator
      return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
      context.coordinator.navigation = navigation
      context.coordinator.library = library
      // Only when it differs: assigning moves the insertion point to the end, which
      // mid-edit would jump the caret on every keystroke.
      if field.stringValue != navigation.searchText {
        field.stringValue = navigation.searchText
      }
    }

    func makeCoordinator() -> Coordinator { Coordinator(navigation: navigation, library: library) }

    /// What a suggestion under the field stands for: a completion, or Search Syntax…,
    /// which opens the help at the search (#781).
    enum Pick: Hashable {
      case suggestion(SearchQuery.Suggestion)
      case syntaxHelp
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate, NSTextSuggestionsDelegate {
      var navigation: NavigationModel
      var library: LibraryModel

      init(navigation: NavigationModel, library: LibraryModel) {
        self.navigation = navigation
        self.library = library
      }

      // MARK: Completion (#21)

      /// AppKit's own suggestions menu under the field: every filter while it is
      /// empty, the qualifier being typed, or its values. A qualifier the search does
      /// not know is shown dimmed, with what becomes of it. Under any of them, Search
      /// Syntax… opens the help at the search (#781): AppKit asks for suggestions only
      /// as the text changes, so an empty field the reader has only clicked into shows
      /// none, and this is the way to the rest of the syntax from there on.
      func textField(
        _ textField: NSTextField,
        provideUpdatedSuggestions responseHandler:
          @escaping (NSSuggestionItemResponse<Pick>) -> Void
      ) {
        guard let index = library.index else { return responseHandler(NSSuggestionItemResponse()) }
        let items = SearchQuery.suggestionsWhileTyping(for: textField.stringValue, in: index).map {
          suggestion in
          var item = NSSuggestionItem(
            representedValue: Pick.suggestion(suggestion), title: suggestion.word)
          if suggestion.isUnknown {
            var title = AttributedString(suggestion.word)
            title.foregroundColor = .secondaryLabelColor
            item.attributedTitle = title
            item.secondaryTitle = String(localized: "Searched as text")
          }
          return item
        }
        guard !items.isEmpty else { return responseHandler(NSSuggestionItemResponse()) }
        let help = NSSuggestionItem(
          representedValue: Pick.syntaxHelp, title: String(localized: "Search Syntax…"))
        responseHandler(
          NSSuggestionItemResponse(itemSections: [
            NSSuggestionItemSection(items: items), NSSuggestionItemSection(items: [help]),
          ]))
      }

      /// No inline completion while a suggestion is highlighted: AppKit's assumes it
      /// extends what was typed, and `is:b` completes to `status:bcp`. Said here
      /// rather than left out, as the protocol has a default of its own.
      func textField(
        _ textField: NSTextField, textCompletionFor item: NSSuggestionItem<Pick>
      ) -> String? {
        nil
      }

      /// Taking a suggestion applies it at once, as Return does: a pick is not
      /// typing, and the list should not wait for a pause.
      func textField(_ textField: NSTextField, didSelect item: NSSuggestionItem<Pick>) {
        guard case .suggestion(let suggestion) = item.representedValue else {
          HelpWindow.show(at: .search)
          return
        }
        textField.stringValue = suggestion.accepted
        navigation.searchText = textField.stringValue
        navigation.commitSearch()
      }

      // MARK: Editing

      /// Every edit, the clear button included, rather than `searchFieldDidEndSearching`
      /// or the field's action: the list filters as the reader types.
      func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField else { return }
        navigation.searchText = field.stringValue
      }

      /// Return applies the search without waiting for a pause in typing.
      func control(
        _ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector
      ) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
          navigation.commitSearch()
        }
        return false
      }
    }
  }
#endif
