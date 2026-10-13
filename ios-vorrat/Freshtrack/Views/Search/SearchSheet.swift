import SwiftUI

/// Bottom sheet for searching pantry products, with a shortcut to the AI chef.
struct SearchSheet: View {
    @Environment(PantryStore.self) private var store
    let onSelect: (Product) -> Void
    let onOpenChef: () -> Void

    @State private var query: String = ""
    @FocusState private var isFocused: Bool

    private var results: [Product] { store.search(query) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                searchField

                if !store.recentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Kürzlich gesucht")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.secondary)
                            Spacer()
                            Button("Löschen") { withAnimation { store.clearRecentSearches() } }
                                .font(.footnote)
                                .foregroundStyle(Theme.secondary)
                        }
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(store.recentSearches, id: \.self) { term in
                                    Button {
                                        query = term
                                    } label: {
                                        Label(term, systemImage: "clock.arrow.circlepath")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 14)
                                            .frame(height: 38)
                                            .glassSurface(Capsule(), interactive: true)
                                    }
                                    .buttonStyle(PressableStyle())
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .scrollClipDisabled()
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(query.isEmpty ? "Dein Freshtrack" : "Ergebnisse")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.secondary)

                    if results.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 26))
                                .foregroundStyle(Theme.secondary)
                            Text(query.isEmpty ? "Noch keine Produkte" : "Nichts gefunden für „\(query)“")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(results) { product in
                                Button {
                                    store.rememberSearch(query)
                                    onSelect(product)
                                } label: {
                                    SearchResultRow(product: product)
                                }
                                .buttonStyle(PressableStyle(scale: 0.98))
                            }
                        }
                    }
                }

                Button(action: onOpenChef) {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 62, height: 62)
                            .glassSurface(Circle(), interactive: true)
                        Text("Zur KI-Koch")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PressableStyle(scale: 0.94))
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .preferredColorScheme(.dark)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            TextField("Produkte durchsuchen", text: $query)
                .font(.body)
                .foregroundStyle(.white)
                .focused($isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { store.rememberSearch(query) }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.secondary)
                }
                .accessibilityLabel("Suche leeren")
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
        .glassSurface(Capsule())
    }
}

private struct SearchResultRow: View {
    let product: Product

    var body: some View {
        HStack(spacing: 14) {
            ProductImage(category: product.category)
                .frame(width: 76, height: 64)
                .clipShape(.rect(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text(product.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("gekauft \(Formatters.shortDate(product.purchasedAt))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.secondary)
        }
        .padding(8)
        .padding(.trailing, 8)
        .contentCard(radius: 20)
    }
}
