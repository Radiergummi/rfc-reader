import RFCKit
import RFCReaderKit
import SwiftUI

#if os(macOS)
  /// The filters the search sets, named under the Mac's search field, each with a
  /// button that removes it from the query (#21). The field itself keeps the query as
  /// typed: `NSSearchField` draws no tokens, and the query stays the one source of
  /// truth. The default search scope's parts in force come first (#713), as chips
  /// that remove it for this search, so a document it leaves out is explained.
  ///
  /// Takes the model rather than reading it out of `SidebarView.body`, for the reason
  /// `SidebarSearchField` does: the dependency on the query reaches no further than
  /// this row.
  struct SearchFilterChips: View {
    let navigation: NavigationModel

    var body: some View {
      // The query the list is filtered by, so a chip names a filter in force.
      let terms = SearchQuery.terms(of: IndexSearch.parseQuery(navigation.appliedQuery).filters)
      let scope = navigation.listOptions.scopeInForce(
        query: navigation.appliedQuery, filter: navigation.filter,
        definition: navigation.definition(of: navigation.filter)
      ).tokens()
      if !terms.isEmpty || !scope.isEmpty {
        ScrollView(.horizontal) {
          HStack(spacing: 4) {
            ForEach(scope) { token in
              chip(label: token.label) {
                navigation.listOptions.searchScope =
                  navigation.listOptions.searchScope.removing(token.part)
              }
            }
            ForEach(terms) { term in
              chip(label: term.label) {
                navigation.searchText = SearchQuery.removing(term, from: navigation.searchText)
                navigation.applySearchWithoutPause()
              }
            }
          }
        }
        .scrollIndicators(.never)
      }
    }

    private func chip(label: String, remove: @escaping () -> Void) -> some View {
      Button(action: remove) {
        HStack(spacing: 3) {
          Text(verbatim: label)
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
      .accessibilityLabel("Remove filter \(label)")
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
  /// what the field shows, and the sidebar's field and the list's agree. The default
  /// search scope's parts in force lead the tokens (#713); removing one removes it
  /// from the tab's scope for this search.
  private struct FilterSearchable: ViewModifier {
    @Environment(LibraryModel.self) private var library
    let navigation: NavigationModel
    let prompt: String

    func body(content: Content) -> some View {
      content
        .searchable(text: text, tokens: tokens, prompt: prompt) { token in
          Text(verbatim: token.label)
        }
        .searchSuggestions {
          if let index = library.index {
            ForEach(suggestions(in: index), id: \.self) {
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

    /// Every filter while the field is empty, which is where the syntax is taught
    /// (#781), but not while it holds tokens and no text: the list would cover the
    /// results after every filter that becomes one.
    private func suggestions(in index: RFCIndex) -> [SearchQuery.Suggestion] {
      let typed = text.wrappedValue
      guard !typed.isEmpty || navigation.searchText.isEmpty else { return [] }
      return SearchQuery.suggestionsWhileTyping(for: typed, in: index)
    }

    private var text: Binding<String> {
      Binding {
        SearchQuery.tokenized(navigation.searchText, workingGroups: library.knownWorkingGroups).text
      } set: { text in
        navigation.searchText = SearchQuery.replacingText(
          in: navigation.searchText, with: text, workingGroups: library.knownWorkingGroups)
      }
    }

    private var tokens: Binding<[FieldToken]> {
      Binding {
        // The text, not the query applied, as the terms are: a token appearing once
        // typing pauses would land in the field while it is typed in.
        let scope = navigation.listOptions.scopeInForce(
          query: navigation.searchText, filter: navigation.searchedFilter,
          definition: navigation.definition(of: navigation.searchedFilter)
        ).tokens()
        let terms = SearchQuery.tokenized(
          navigation.searchText, workingGroups: library.knownWorkingGroups
        ).terms
        return scope.map(FieldToken.scope) + terms.map(FieldToken.term)
      } set: { tokens in
        let scope = navigation.listOptions.scopeInForce(
          query: navigation.searchText, filter: navigation.searchedFilter,
          definition: navigation.definition(of: navigation.searchedFilter))
        let kept = Set(tokens.compactMap(\.scopePart))
        for token in scope.tokens() where !kept.contains(token.part) {
          navigation.listOptions.searchScope =
            navigation.listOptions.searchScope.removing(token.part)
        }
        navigation.searchText = SearchQuery.replacingTerms(
          in: navigation.searchText, with: tokens.compactMap(\.term),
          workingGroups: library.knownWorkingGroups)
      }
    }
  }

  /// A token of the iOS search field: a part of the default search scope, or a
  /// filter of the query.
  private enum FieldToken: Hashable, Identifiable {
    case scope(SearchScope.Token)
    case term(SearchQuery.Term)

    var id: String {
      switch self {
      case .scope(let token): "scope:\(token.part)"
      case .term(let term): term.id
      }
    }

    var label: String {
      switch self {
      case .scope(let token): token.label
      case .term(let term): term.label
      }
    }

    var scopePart: SearchScope.Part? {
      if case .scope(let token) = self { token.part } else { nil }
    }

    var term: SearchQuery.Term? {
      if case .term(let term) = self { term } else { nil }
    }
  }
#endif
