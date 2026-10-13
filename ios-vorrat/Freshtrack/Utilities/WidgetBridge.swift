import Foundation
import WidgetKit

nonisolated struct WidgetProduct: Codable {
    var name: String
    var quantity: String
    var price: Double
}

/// Kleiner, widget-fähiger Zustands-Snapshot (Budget + letzter Kassenbon).
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

/// Schreibt den Widget-Snapshot in die gemeinsamen UserDefaults der
/// App-Group (gemeinsame UserDefaults UND Container-Datei, doppelt
/// abgesichert) und fordert die Widgets zum Neuladen auf.
nonisolated enum WidgetBridge {
    static let appGroupID = "group.app.rork.fwa5bgudhsakfldvz720v.shared"
    private static let snapshotKey = "widgetSnapshotData"
    private static let fileName = "widget-snapshot.json"

    static func push(products: [Product], purchases: [Purchase], stores: [SavedStore], monthSpent: Double, budget: Double) {
        let last = purchases.max { $0.date < $1.date }
        let lastStoreName = last?.store
        let lastStoreColor = lastStoreName.flatMap { name in
            stores.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.colorHex
        }
        let snapshot = WidgetSnapshotData(
            monthSpent: monthSpent,
            monthlyBudget: budget,
            lastStore: lastStoreName,
            lastStoreColorHex: lastStoreColor,
            lastPurchaseDate: last?.date,
            lastPurchaseTotal: last?.total,
            lastPurchaseItemCount: last?.itemCount,
            recentProducts: products
                .sorted { $0.purchasedAt > $1.purchasedAt }
                .prefix(4)
                .map { WidgetProduct(name: $0.name, quantity: $0.quantity, price: $0.price) }
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: appGroupID)?.set(data, forKey: snapshotKey)
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            try? data.write(to: container.appendingPathComponent(fileName), options: .atomic)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
