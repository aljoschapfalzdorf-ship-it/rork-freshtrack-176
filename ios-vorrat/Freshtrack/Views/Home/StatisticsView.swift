import SwiftUI

/// Pro-Statistiken: Wochenverlauf, Kategorien und größte Ausgaben des Monats.
struct StatisticsView: View {
    @Environment(PantryStore.self) private var store
    @Environment(ProManager.self) private var pro
    @Environment(\.dismiss) private var dismiss

    @State private var showsPaywall: Bool = false

    var body: some View {
        NavigationStack {
            Group {
                if pro.isPro {
                    statistics
                } else {
                    locked
                }
            }
            .background(AtmosphereBackground())
            .navigationTitle("Statistiken")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
        .sheet(isPresented: $showsPaywall) {
            ProPaywallView()
        }
    }

    // MARK: Pro content

    private var statistics: some View {
        ScrollView {
            VStack(spacing: 14) {
                headerTiles

                if store.monthSpent <= 0 {
                    emptyNote
                } else {
                    weekCard
                    if !categorySpend.isEmpty {
                        categoryCard
                    }
                    if !topExpenses.isEmpty {
                        topCard
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    private var headerTiles: some View {
        HStack(spacing: 10) {
            statTile(value: "\(purchasesThisMonth.count)", label: "Einkäufe")
            statTile(value: Formatters.euro(avgPerPurchase), label: "Ø Einkauf")
            statTile(value: Formatters.euro(max(store.monthlyBudget - store.monthSpent, 0)), label: "Budget offen")
        }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .contentCard(radius: 20)
    }

    private var emptyNote: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.secondary)
            Text("Noch keine Ausgaben in diesem Monat")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
            Text("Scanne einen Kassenbon – dann siehst du hier, wofür dein Geld ausgegeben wird.")
                .font(.caption)
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .contentCard()
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Ausgaben pro Woche")
            HStack(alignment: .bottom, spacing: 16) {
                ForEach(weekBuckets, id: \.label) { bucket in
                    VStack(spacing: 8) {
                        Text(bucket.total > 0 ? Formatters.euro(bucket.total) : "–")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.45)], startPoint: .top, endPoint: .bottom))
                            .frame(height: barHeight(for: bucket.total))
                        Text(bucket.label)
                            .font(.caption2)
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 130, alignment: .bottom)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard()
    }

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Nach Kategorie")
            let maxTotal = categorySpend.first?.total ?? 0
            ForEach(categorySpend, id: \.category) { entry in
                HStack(spacing: 12) {
                    Text(categoryName(entry.category))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 104, alignment: .leading)
                        .lineLimit(1)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.10))
                            Capsule()
                                .fill(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.55)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: entry.total > 0 ? max(geo.size.width * entry.total / max(maxTotal, 0.01), 8) : 0)
                        }
                    }
                    .frame(height: 8)
                    Text(Formatters.euro(entry.total))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .frame(width: 64, alignment: .trailing)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard()
    }

    private var topCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Größte Ausgaben")
                .padding(.bottom, 10)
            ForEach(Array(topExpenses.enumerated()), id: \.element.id) { index, product in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 22, height: 22)
                        .background(Theme.surfaceHigh, in: .circle)
                    Text(product.name)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Text(Formatters.euro(product.price))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                .padding(.vertical, 9)
                if index < topExpenses.count - 1 {
                    Divider().overlay(Theme.hairline)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard()
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.secondary)
            .textCase(.uppercase)
    }

    private func barHeight(for total: Double) -> CGFloat {
        let maxTotal = weekBuckets.map(\.total).max() ?? 0
        guard maxTotal > 0 else { return 6 }
        return total > 0 ? 12 + CGFloat(total / maxTotal) * 72 : 6
    }

    // MARK: Locked

    private var locked: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white)
                .frame(width: 78, height: 78)
                .background(Color.white.opacity(0.08), in: .circle)
            Text("Erweiterte Statistiken")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text("Sieh mit Vorrat Pro, wofür dein Geld ausgegeben wird – pro Woche, Kategorie und Produkt.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            Button {
                showsPaywall = true
            } label: {
                Text("Mit Pro freischalten")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(.white, in: .capsule)
            }
            .buttonStyle(PressableStyle())
            .padding(.horizontal, 10)
            .padding(.top, 4)
            Text("\(pro.priceText) / Monat · jederzeit kündbar")
                .font(.caption)
                .foregroundStyle(Theme.secondary)
            Spacer()
        }
        .padding(28)
    }

    // MARK: Data

    private var purchasesThisMonth: [Purchase] { store.purchasesThisMonth }

    private var avgPerPurchase: Double {
        let count = purchasesThisMonth.count
        guard count > 0 else { return 0 }
        return store.monthSpent / Double(count)
    }

    private var monthProducts: [Product] {
        store.products.filter { store.calendar.isDate($0.purchasedAt, equalTo: .now, toGranularity: .month) }
    }

    private var weekBuckets: [(label: String, total: Double)] {
        let cal = store.calendar
        guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
        return (0..<4).reversed().compactMap { back in
            guard let start = cal.date(byAdding: .weekOfYear, value: -back, to: thisWeek),
                  let end = cal.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            let total = store.purchases.filter { $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.total }
            let label = back == 0
                ? "Aktuell"
                : start.formatted(.dateTime.day(.twoDigits).month(.twoDigits).locale(Formatters.german))
            return (label, total)
        }
    }

    private var categorySpend: [(category: ProductCategory, total: Double)] {
        Dictionary(grouping: monthProducts, by: \.category)
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.price }) }
            .sorted { $0.total > $1.total }
    }

    private var topExpenses: [Product] {
        monthProducts.sorted { $0.price > $1.price }.prefix(5).map { $0 }
    }

    private func categoryName(_ category: ProductCategory) -> String {
        switch category {
        case .dairy: "Milchprodukte"
        case .eggs: "Eier"
        case .rice: "Reis"
        case .tomatoes: "Tomaten"
        case .bananas: "Bananen"
        case .vegetables: "Gemüse"
        case .bread: "Brot & Gebäck"
        case .cheese: "Käse"
        case .pasta: "Nudeln"
        case .fruit: "Obst"
        case .meat: "Fleisch & Fisch"
        case .drinks: "Getränke"
        case .cereal: "Cerealien"
        case .other: "Sonstiges"
        }
    }
}

#Preview {
    StatisticsView()
        .environment(PantryStore())
        .environment(ProManager())
}
