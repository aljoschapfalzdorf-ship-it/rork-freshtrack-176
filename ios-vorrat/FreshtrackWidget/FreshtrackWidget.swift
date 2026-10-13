import WidgetKit
import SwiftUI

// MARK: - Daten (Spiegel der App-Group-Struktur)

nonisolated struct WidgetProduct: Codable {
    var name: String
    var quantity: String
    var price: Double
}

nonisolated struct WidgetSnapshotData: Codable {
    var monthSpent: Double
    var monthlyBudget: Double
    var lastStore: String?
    var lastStoreColorHex: String?
    var lastPurchaseDate: Date?
    var lastPurchaseTotal: Double?
    var lastPurchaseItemCount: Int?
    var recentProducts: [WidgetProduct]
}

// MARK: - Timeline

nonisolated struct PantryEntry: TimelineEntry {
    let date: Date
    let data: WidgetSnapshotData?
}

nonisolated struct Provider: TimelineProvider {
    private static let appGroupID = "group.app.rork.fwa5bgudhsakfldvz720v.shared"
    private static let snapshotKey = "widgetSnapshotData"
    private static let fileName = "widget-snapshot.json"

    /// Liest den Snapshot über beide Wege: gemeinsame UserDefaults und
    /// Container-Datei (falls einer der Wege blockiert ist).
    static func loadSnapshot() -> WidgetSnapshotData? {
        if let data = UserDefaults(suiteName: appGroupID)?.data(forKey: snapshotKey),
           let snapshot = try? JSONDecoder().decode(WidgetSnapshotData.self, from: data) {
            return snapshot
        }
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID),
              let data = try? Data(contentsOf: container.appendingPathComponent(fileName)) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshotData.self, from: data)
    }

    func placeholder(in context: Context) -> PantryEntry {
        PantryEntry(date: .now, data: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PantryEntry) -> Void) {
        completion(PantryEntry(date: .now, data: Self.loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PantryEntry>) -> Void) {
        let entry = PantryEntry(date: .now, data: Self.loadSnapshot())
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Helpers

private let german = Locale(identifier: "de_DE")

private func euro(_ value: Double) -> String {
    value.formatted(.currency(code: "EUR").locale(german))
}

private func monthName(_ date: Date) -> String {
    date.formatted(.dateTime.month(.wide).locale(german))
}

private func shortDate(_ date: Date) -> String {
    date.formatted(.dateTime.day().month(.abbreviated).locale(german))
}

private func brandColor(_ hex: String?) -> Color {
    guard let hex, hex.count >= 7, let rgb = UInt64(hex.dropFirst(), radix: 16) else { return .white.opacity(0.4) }
    return Color(
        red: Double((rgb >> 16) & 0xFF) / 255,
        green: Double((rgb >> 8) & 0xFF) / 255,
        blue: Double(rgb & 0xFF) / 255
    )
}

/// Fortschrittsring fürs Budget.
private struct BudgetRing: View {
    let progress: Double
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.14), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(to: min(progress, 1))
                .stroke(.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Budget-Sektion (immer sichtbar)

private struct BudgetSection: View {
    let entry: Provider.Entry
    let ringSize: CGFloat
    let lineWidth: CGFloat
    let percentSize: CGFloat
    let amountSize: CGFloat

    private var data: WidgetSnapshotData? { entry.data }

    var body: some View {
        let spent = data?.monthSpent ?? 0
        let budget = data?.monthlyBudget ?? 0
        let progress = budget > 0 ? min(spent / budget, 1) : 0

        HStack(spacing: 16) {
            ZStack {
                BudgetRing(progress: progress, lineWidth: lineWidth)
                Text(budget > 0 ? "\(Int((progress * 100).rounded())) %" : "–")
                    .font(.system(size: percentSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
            }
            .frame(width: ringSize, height: ringSize)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(euro(spent))
                        .font(.system(size: amountSize, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    if budget > 0 {
                        Text("von \(euro(budget))")
                            .font(.system(size: amountSize * 0.55, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                if budget > 0 {
                    let remaining = budget - spent
                    Text(remaining >= 0 ? "Noch \(euro(remaining)) übrig" : "\(euro(-remaining)) übers Limit")
                        .font(.system(size: amountSize * 0.5, weight: .semibold))
                        .foregroundStyle(remaining >= 0 ? .white.opacity(0.5) : Color(red: 1, green: 0.23, blue: 0.19))
                } else {
                    Text("Budget in der App festlegen")
                        .font(.system(size: amountSize * 0.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Kleines Widget

private struct SmallWidgetView: View {
    let entry: Provider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("BUDGET")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text(monthName(entry.date))
                    .font(.system(size: 9, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.5))
            }

            BudgetSection(entry: entry, ringSize: 62, lineWidth: 7, percentSize: 17, amountSize: 18)
                .frame(maxWidth: .infinity)
        }
        .padding(2)
    }
}

// MARK: - Großes Widget

private struct LargeWidgetView: View {
    let entry: Provider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Vorrat")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text("Budget \(monthName(entry.date))")
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.5))
            }

            BudgetSection(entry: entry, ringSize: 60, lineWidth: 8, percentSize: 15, amountSize: 22)

            divider

            lastPurchaseSection

            divider

            recentSection

            Spacer(minLength: 0)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.1))
            .frame(height: 1)
    }

    private var lastPurchaseSection: some View {
        let data = entry.data
        return VStack(alignment: .leading, spacing: 6) {
            Text("LETZTER EINKAUF")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.5))
            if let store = data?.lastStore {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(brandColor(data?.lastStoreColorHex))
                            .frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(store)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            if let date = data?.lastPurchaseDate {
                                Text("\(shortDate(date)) · \(data?.lastPurchaseItemCount ?? 0) Artikel")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }
                    Spacer()
                    if let total = data?.lastPurchaseTotal {
                        Text(euro(total))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
            } else {
                Text("Noch kein Einkauf erfasst")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var recentSection: some View {
        let products = entry.data?.recentProducts ?? []
        return VStack(alignment: .leading, spacing: 6) {
            Text("ZULETZT HINZUGEFÜGT")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.5))
            if products.isEmpty {
                Text("Dein Vorrat ist leer")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                ForEach(Array(products.prefix(3).enumerated()), id: \.offset) { _, product in
                    HStack(alignment: .firstTextBaseline) {
                        Text(product.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(product.quantity)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                        Spacer()
                        Text(euro(product.price))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
    }
}

// MARK: - Widget-Konfiguration

private struct PantryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: Provider.Entry

    var body: some View {
        Group {
            switch family {
            case .systemLarge: LargeWidgetView(entry: entry)
            default: SmallWidgetView(entry: entry)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(Color(white: 0.04), for: .widget)
    }
}

struct FreshtrackWidget: Widget {
    let kind: String = "FreshtrackWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PantryWidgetView(entry: entry)
        }
        .configurationDisplayName("Vorrat")
        .description("Budget und dein letzter Kassenbon auf einen Blick.")
        .supportedFamilies([.systemSmall, .systemLarge])
    }
}
