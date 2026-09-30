import RFCKit
import SwiftUI

#if os(macOS)
  /// The filters the search sets, named under the Mac's search field, each with a
  /// button that removes it from the query (#21). The field itself keeps the query as
  /// typed: `NSSearchField` draws no tokens, and the query stays the one source of
  /// truth.
  ///
  /// Takes the model rather than reading it out of `SidebarView.body`, for the reason
  /// `SidebarSearchField` does: the dependency on the query reaches no further than
  /// this row.
  struct SearchFilterChips: View {
    let navigation: NavigationModel

    var body: some View {
      // The query the list is filtered by, so a chip names a filter in force.
      let terms = SearchQuery.terms(of: IndexSearch.parseQuery(navigation.appliedQuery).filters)
      if !terms.isEmpty {
        ScrollView(.horizontal) {
          HStack(spacing: 4) {
            ForEach(terms) { term in
              chip(term)
            }
          }
        }
        .scrollIndicators(.never)
      }
    }

    private func chip(_ term: SearchQuery.Term) -> some View {
      Button {
        navigation.searchText = SearchQuery.removing(term, from: navigation.searchText)
        navigation.applySearchWithoutPause()
      } label: {
        HStack(spacing: 3) {
          Text(term.label)
          Image(systemName: "xmark")
            .imageScale(.small)
            .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.quaternary, in: .capsule)
      }
      .buttonStyle(.plain)
      .help("Remove this filter")
      .accessibilityLabel("Remove filter \(term.label)")
    }
  }
#else
  extension View {
    /// A search field over the one search text whose finished filters are tokens
    /// and whose qualifiers are completed as they are typed (#21).
    func filterSearchable(navigation: NavigationModel, prompt: String) -> some View {
      modifier(FilterSearchable(navigation: navigation, prompt: prompt))
    }
  }

  /// `.searchable(text:tokens:)` over `NavigationModel.searchText`. The tokens and the
  /// text are a view of that one string, `SearchQuery.tokenized`, and every edit of
  /// either writes it back with `replacingText` or `replacingTerms`, so the list filters on exactly
  /// what the field shows, and the sidebar's field and the list's agree.
  private struct FilterSearchable: ViewModifier {
    @Environment(LibraryModel.self) private var library
    let navigation: NavigationModel
    let prompt: String

    func body(content: Content) -> some View {
      content
        .searchable(text: text, tokens: tokens, prompt: prompt) { term in
          Text(term.label)
        }
        .searchSuggestions {
          if let index = library.index {
            ForEach(
              SearchQuery.suggestionsWhileTyping(for: text.wrappedValue, in: index), id: \.self
            ) {
              suggestion in
              if suggestion.isUnknown {
                Label("\(suggestion.word): searched as text", systemImage: "questionmark.circle")
                  .foregroundStyle(.secondary)
              } else {
                Text(suggestion.word).searchCompletion(suggestion.accepted)
              }
            }
          }
        }
    }

    private var text: Binding<String> {
      Binding {
        SearchQuery.tokenized(navigation.searchText, workingGroups: library.knownWorkingGroups).text
      } set: { text in
        navigation.searchText = SearchQuery.replacingText(
          in: navigation.searchText, with: text, workingGroups: library.knownWorkingGroups)
      }
    }

    private var tokens: Binding<[SearchQuery.Term]> {
      Binding {
        SearchQuery.tokenized(navigation.searchText, workingGroups: library.knownWorkingGroups)
          .terms
      } set: { terms in
        navigation.searchText = SearchQuery.replacingTerms(
          in: navigation.searchText, with: terms, workingGroups: library.knownWorkingGroups)
      }
    }
  }
#endif
