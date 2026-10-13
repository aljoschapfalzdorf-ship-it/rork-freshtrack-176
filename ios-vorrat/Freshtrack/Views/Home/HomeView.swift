import SwiftUI

/// "Zuhause" tab: life estimate, monthly spending and the pantry feed.
struct HomeView: View {
    @Environment(PantryStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var path: [Product] = []
    @State private var showScanner: Bool = false
    @State private var showSearch: Bool = false
    @State private var showOverview: Bool = false
    @State private var showStatistics: Bool = false
    @State private var selectedStore: String?
    @State private var deleteTick: Int = 0

    private var visibleProducts: [Product] {
        guard let selectedStore else { return store.products }
        return store.products.filter { $0.store == selectedStore }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Text("Geschätzt: \(Formatters.months(store.monthsRemaining)) Monate verbleibend")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText())
                    .onTapGesture { showOverview = true }
                    .accessibilityAddTraits(.isButton)
                    .plainRow(top: 4, bottom: 6)

                Button { showOverview = true } label: {
                    SpendingCard(spent: store.monthSpent, progress: store.budgetProgress, daysUntilReset: store.daysUntilReset)
                }
                .buttonStyle(PressableStyle(scale: 0.98))
                .overlay(alignment: .topTrailing) {
                    Button {
                        showStatistics = true
                    } label: {
                        Label("Statistiken", systemImage: "chart.bar.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassSurface(Capsule(), interactive: true)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Statistiken öffnen")
                    .padding(10)
                }
                .plainRow(top: 6, bottom: 10)

                if !store.stores.isEmpty {
                    StoreSlider(stores: store.stores, selection: $selectedStore)
                        .plainRow(top: 0, bottom: 8)
                }

                if store.products.isEmpty {
                    EmptyPantryCard { showScanner = true }
                        .plainRow(top: 6, bottom: 6)
                } else {
                    ForEach(visibleProducts) { product in
                        Button { path.append(product) } label: {
                            ProductCard(product: product, isFresh: store.freshlyAdded.contains(product.id))
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                        .plainRow(top: 6, bottom: 6)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                delete(product)
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                            .tint(Theme.destructive)
                        }
                        .contextMenu {
                            Button { router.askChef("Was kann ich mit \(product.name) kochen?") } label: {
                                Label("Rezept mit KI", systemImage: "sparkles")
                            }
                            Button(role: .destructive) { delete(product) } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .background(AtmosphereBackground())
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.products)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: visibleProducts)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    GlassCircleButton(systemImage: "magnifyingglass", size: 62, iconSize: 22, label: "Suchen") {
                        showSearch = true
                    }
                    Spacer()
                    GlassCircleButton(systemImage: "qrcode.viewfinder", size: 62, iconSize: 24, label: "Kassenbon scannen") {
                        showScanner = true
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Product.self) { product in
                ProductDetailView(productID: product.id)
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            ScanView()
        }
        .sheet(isPresented: $showSearch) {
            SearchSheet(
                onSelect: { product in
                    showSearch = false
                    path = [product]
                },
                onOpenChef: {
                    showSearch = false
                    router.tab = .chef
                }
            )
        }
        .sheet(isPresented: $showOverview) {
            MonthOverviewSheet()
        }
        .sheet(isPresented: $showStatistics) {
            StatisticsView()
        }
        .task(id: store.freshlyAdded) {
            guard !store.freshlyAdded.isEmpty else { return }
            try? await Task.sleep(for: .seconds(5))
            withAnimation(.easeOut) { store.freshlyAdded = [] }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: deleteTick)
    }

    private func delete(_ product: Product) {
        deleteTick += 1
        withAnimation { store.delete(product) }
    }
}

private struct EmptyPantryCard: View {
    let onScan: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "basket")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(Color.white.opacity(0.08), in: .circle)
            Text("Dein Freshtrack ist leer")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("Scanne deinen nächsten Kassenbon – die Texterkennung auf deinem Gerät erkennt alle Produkte und legt sie hier ab.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
            Button(action: onScan) {
                Label("Kassenbon scannen", systemImage: "qrcode.viewfinder")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.white, in: .capsule)
            }
            .buttonStyle(PressableStyle())
            .padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .contentCard()
    }
}

extension View {
    /// Transparent, separator-less list row with card spacing.
    func plainRow(top: CGFloat, bottom: CGFloat) -> some View {
        self
            .listRowInsets(EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

/// Horizontaler Slider: "Alle Läden" plus ein Chip pro gespeichertem Laden,
/// mit Markenfarb-Punkt als Daten-Akzent. Langes Drücken öffnet Bearbeiten/Löschen.
private struct StoreSlider: View {
    @Environment(PantryStore.self) private var store
    let stores: [SavedStore]
    @Binding var selection: String?

    @State private var actionStore: SavedStore?
    @State private var showActions: Bool = false
    @State private var editStore: SavedStore?
    @State private var pressTick: Int = 0

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Alle Läden", colorHex: nil, isSelected: selection == nil) {
                    selection = nil
                }
                ForEach(stores) { saved in
                    chip(saved.name, colorHex: saved.colorHex, isSelected: selection == saved.name) {
                        selection = selection == saved.name ? nil : saved.name
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.45)
                            .onEnded { _ in
                                actionStore = saved
                                pressTick += 1
                                showActions = true
                            }
                    )
                    .accessibilityHint("Gedrückt halten zum Bearbeiten oder Löschen")
                }
            }
            .padding(.horizontal, 16)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: pressTick)
        .confirmationDialog(
            actionStore?.name ?? "",
            isPresented: $showActions,
            titleVisibility: .visible
        ) {
            Button("Bearbeiten") { editStore = actionStore }
            Button("Löschen", role: .destructive) {
                guard let name = actionStore?.name else { return }
                if selection?.caseInsensitiveCompare(name) == .orderedSame { selection = nil }
                store.deleteStore(name)
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Beim Löschen wandern die Produkte dieses Ladens in „Alle Läden“.")
        }
        .sheet(item: $editStore) { saved in
            StoreEditSheet(original: saved) { newName, colorHex in
                store.updateStore(saved.name, name: newName, colorHex: colorHex)
                if selection?.caseInsensitiveCompare(saved.name) == .orderedSame { selection = newName }
            }
        }
    }

    private func chip(_ title: String, colorHex: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(colorHex.flatMap(Color.init(hex:)) ?? Theme.secondary)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isSelected ? .black : .white)
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .background {
            if isSelected {
                Capsule().fill(.white)
            } else {
                Capsule().fill(.clear).glassSurface(Capsule(), interactive: true)
            }
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel("\(title) anzeigen")
    }
}

/// Bearbeiten-Sheet für einen Laden-Slider: Name + Markenfarbe.
private struct StoreEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let originalName: String
    private let onSave: (String, String?) -> Void

    @State private var name: String
    @State private var colorHex: String?

    /// Kuratierte Palette aus den Markenfarben des Katalogs.
    private static let palette: [String] = [
        "#CC071E", "#E66A00", "#FFCC00", "#78A22F",
        "#00713A", "#0050AA", "#23419F", "#05164D"
    ]

    init(original: SavedStore, onSave: @escaping (String, String?) -> Void) {
        self.originalName = original.name
        self.onSave = onSave
        self._name = State(initialValue: original.name)
        self._colorHex = State(initialValue: original.colorHex)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Laden bearbeiten")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text(originalName)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
            }

            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .padding(16)
                .background(Color.white.opacity(0.08), in: .rect(cornerRadius: 14))
                .submitLabel(.done)
                .onSubmit { save() }

            VStack(alignment: .leading, spacing: 12) {
                Text("FARBE")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 5), spacing: 14) {
                    swatch(color: nil, label: "Ohne")
                    ForEach(Self.palette, id: \.self) { hex in
                        swatch(color: Color(hex: hex), label: hex)
                    }
                }
            }

            Spacer()

            Button(action: save) {
                Text("Speichern")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(.white, in: .capsule)
            }
            .buttonStyle(PressableStyle())
            .disabled(trimmedName.isEmpty)
            .opacity(trimmedName.isEmpty ? 0.4 : 1)
        }
        .padding(24)
        .background(Color.black.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }

    private func swatch(color: Color?, label: String) -> some View {
        Button {
            colorHex = label == "Ohne" ? nil : label
        } label: {
            ZStack {
                Circle()
                    .fill(color ?? Theme.secondary)
                    .frame(width: 40, height: 40)
                if (colorHex == nil && label == "Ohne") || colorHex == label {
                    Circle()
                        .stroke(.white, lineWidth: 2)
                        .frame(width: 50, height: 50)
                }
            }
            .frame(height: 54)
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(label == "Ohne" ? "Keine Farbe" : "Farbe \(label)")
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        onSave(trimmedName, colorHex)
        dismiss()
    }
}
