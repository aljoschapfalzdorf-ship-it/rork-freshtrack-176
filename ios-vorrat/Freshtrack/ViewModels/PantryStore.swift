import Foundation
import Observation

private nonisolated struct PantrySnapshot: Codable {
    var products: [Product]
    var purchases: [Purchase]
    var birthDate: Date?
    var lifeExpectancyYears: Int
    var monthlyBudget: Double
    var recentSearches: [String]
    var hasSeeded: Bool
    var stores: [SavedStore]?
}

/// Single source of truth for pantry items, receipts, spending and life estimate.
@Observable
final class PantryStore {
    private(set) var products: [Product] = []
    private(set) var purchases: [Purchase] = []
    var birthDate: Date? { didSet { save() } }
    var lifeExpectancyYears: Int = 81 { didSet { save() } }
    var monthlyBudget: Double = 400 { didSet { save() } }
    private(set) var recentSearches: [String] = []
    /// Store sliders the user created ("Alle Läden" plus one chip per store).
    private(set) var stores: [SavedStore] = []
    /// Ids of products added by the latest scan, for a short highlight.
    var freshlyAdded: Set<UUID> = []

    private let fileName = "vorrat.json"
    private var isLoading = false

    init() {
        load()
    }

    // MARK: Derived

    var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Formatters.german
        return cal
    }

    var monthSpent: Double {
        let now = Date.now
        return purchases
            .filter { calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.total }
    }

    var budgetProgress: Double {
        guard monthlyBudget > 0 else { return 0 }
        return min(monthSpent / monthlyBudget, 1)
    }

    var daysUntilReset: Int {
        let now = Date.now
        guard let interval = calendar.dateInterval(of: .month, for: now) else { return 0 }
        let startToday = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: startToday, to: interval.end).day ?? 0
        return max(days, 1)
    }

    var currentMonthName: String {
        Date.now.formatted(.dateTime.month(.wide).locale(Formatters.german))
    }

    /// Assumes age 27 until the user sets a birthday.
    var monthsRemaining: Int {
        let now = Date.now
        let birth = birthDate ?? calendar.date(byAdding: .year, value: -27, to: now) ?? now
        guard let end = calendar.date(byAdding: .year, value: lifeExpectancyYears, to: birth) else { return 0 }
        let months = calendar.dateComponents([.month], from: now, to: end).month ?? 0
        return max(months, 0)
    }

    var purchasesThisMonth: [Purchase] {
        purchases
            .filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .month) }
            .sorted { $0.date > $1.date }
    }

    var earlierPurchases: [Purchase] {
        purchases
            .filter { !calendar.isDate($0.date, equalTo: .now, toGranularity: .month) }
            .sorted { $0.date > $1.date }
    }

    /// Short lines for the AI chef, e.g. "Basmati Reis (1 kg)".
    var pantryDescription: [String] {
        products.map { "\($0.name) (\($0.quantity))" }
    }

    func search(_ query: String) -> [Product] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return products }
        return products.filter { $0.name.localizedStandardContains(q) }
    }

    // MARK: Mutations

    /// True, wenn der Laden schon als eigener Slider existiert.
    func hasStore(_ name: String) -> Bool {
        stores.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Legt einen neuen Laden-Slider an (idempotent) und liefert ihn zurück.
    @discardableResult
    func addStore(name: String, colorHex: String?) -> SavedStore {
        if let existing = stores.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        let saved = SavedStore(name: name, colorHex: colorHex)
        stores.append(saved)
        save()
        return saved
    }

    /// Benennt einen Laden-Slider um / ändert seine Farbe und verschiebt
    /// zugeordnete Produkte mit. Ein Name, der schon existiert, wird zusammengelegt.
    func updateStore(_ oldName: String, name newName: String, colorHex: String?) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard let index = stores.firstIndex(where: { $0.name.caseInsensitiveCompare(oldName) == .orderedSame }) else { return }
        if let otherIndex = stores.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame && $0.name.caseInsensitiveCompare(oldName) != .orderedSame }) {
            let target = stores[otherIndex].name
            stores.remove(at: index)
            reassignProducts(from: oldName, to: target)
        } else {
            stores[index].name = trimmed
            stores[index].colorHex = colorHex
            reassignProducts(from: oldName, to: trimmed)
        }
        save()
    }

    /// Entfernt den Slider; die Produkte wandern zurück in "Alle Läden".
    func deleteStore(_ name: String) {
        stores.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        reassignProducts(from: name, to: nil)
        save()
    }

    private func reassignProducts(from oldName: String, to newName: String?) {
        for index in products.indices where products[index].store?.caseInsensitiveCompare(oldName) == .orderedSame {
            products[index].store = newName
        }
    }

    func add(receipt: ScannedReceipt, assignStore: Bool = true) {
        let selected = receipt.items.filter(\.isSelected)
        guard !selected.isEmpty else { return }
        let date = receipt.date ?? .now
        // Ohne Zuordnung landen die Produkte ausschließlich im Slider "Alle Läden".
        let canonicalStore = stores.first { $0.name.caseInsensitiveCompare(receipt.store) == .orderedSame }?.name
        let productStore = assignStore ? (canonicalStore ?? receipt.store) : nil
        let newProducts: [Product] = selected.map {
            Product(name: $0.name, quantity: $0.quantity, price: $0.price, category: $0.category, purchasedAt: date, store: productStore)
        }
        let itemTotal = selected.reduce(0) { $0 + $1.price }
        let allSelected = selected.count == receipt.items.count
        let total = allSelected ? (receipt.total ?? itemTotal) : itemTotal
        purchases.append(Purchase(store: receipt.store, date: date, total: total, itemCount: selected.count))
        products.insert(contentsOf: newProducts, at: 0)
        freshlyAdded = Set(newProducts.map(\.id))
        save()
    }

    func delete(_ product: Product) {
        products.removeAll { $0.id == product.id }
        save()
    }

    func deletePurchase(_ purchase: Purchase) {
        purchases.removeAll { $0.id == purchase.id }
        save()
    }

    func rememberSearch(_ term: String) {
        let t = term.trimmingCharacters(in: .whitespaces)
        guard t.count > 1 else { return }
        recentSearches.removeAll { $0.caseInsensitiveCompare(t) == .orderedSame }
        recentSearches.insert(t, at: 0)
        recentSearches = Array(recentSearches.prefix(6))
        save()
    }

    func clearRecentSearches() {
        recentSearches = []
        save()
    }

    // MARK: Persistence

    private func load() {
        isLoading = true
        defer { isLoading = false }
        if let snapshot = Persistence.load(PantrySnapshot.self, from: fileName) {
            products = snapshot.products
            purchases = snapshot.purchases
            birthDate = snapshot.birthDate
            lifeExpectancyYears = snapshot.lifeExpectancyYears
            monthlyBudget = snapshot.monthlyBudget
            recentSearches = snapshot.recentSearches
            stores = snapshot.stores ?? []
        } else {
            seed()
        }
        // Widgets bei jedem App-Start mit frischen Daten versorgen.
        WidgetBridge.push(products: products, purchases: purchases, stores: stores, monthSpent: monthSpent, budget: monthlyBudget)
    }

    private func save() {
        guard !isLoading else { return }
        let snapshot = PantrySnapshot(
            products: products,
            purchases: purchases,
            birthDate: birthDate,
            lifeExpectancyYears: lifeExpectancyYears,
            monthlyBudget: monthlyBudget,
            recentSearches: recentSearches,
            hasSeeded: true,
            stores: stores
        )
        Persistence.save(snapshot, to: fileName)
        // 80-%-Budget-Hinweis prüfen (max. einmal pro Monat).
        BudgetNotificationService.shared.check(monthSpent: monthSpent, budget: monthlyBudget)
        // Widgets mit frischem Budget + letztem Kassenbon versorgen.
        WidgetBridge.push(products: products, purchases: purchases, stores: stores, monthSpent: monthSpent, budget: monthlyBudget)
    }

    /// Persistiert den aktuellen Stand und aktualisiert die Widgets —
    /// für den Sync bei App-Start, Vordergrund und Hintergrund.
    func syncWidget() {
        save()
    }

    /// Entfernt sämtliche lokal gespeicherten Daten (Freshtrack-Datei,
    /// KI-Koch-Chat, KI-Bilder) und setzt den Store auf Werkszustand zurück —
    /// z. B. beim Löschen des Accounts.
    func deleteAllLocalData() {
        let files = [fileName, "chef_chat.json"]
        for file in files {
            try? FileManager.default.removeItem(at: Persistence.documents.appendingPathComponent(file))
        }
        if let contents = try? FileManager.default.contentsOfDirectory(at: Persistence.documents, includingPropertiesForKeys: nil) {
            for file in contents where file.lastPathComponent.hasPrefix("dish_") {
                try? FileManager.default.removeItem(at: file)
            }
        }
        products = []
        purchases = []
        stores = []
        recentSearches = []
        birthDate = nil
        lifeExpectancyYears = 81
        monthlyBudget = 400
        save()
    }

    /// First-launch example so the app never opens empty.
    private func seed() {
        let now = Date.now
        func daysAgo(_ d: Int) -> Date { calendar.date(byAdding: .day, value: -d, to: now) ?? now }
        products = [
            Product(name: "Vollmilch 3,8%", quantity: "1 l", price: 1.19, category: .dairy, purchasedAt: daysAgo(0), store: "Beispiel-Einkauf"),
            Product(name: "Bio-Eier 10er", quantity: "10 Stück", price: 3.49, category: .eggs, purchasedAt: daysAgo(0), store: "Beispiel-Einkauf"),
            Product(name: "Basmati Reis", quantity: "1 kg", price: 2.99, category: .rice, purchasedAt: daysAgo(0), store: "Beispiel-Einkauf"),
            Product(name: "Cherry Tomaten", quantity: "500 g", price: 2.29, category: .tomatoes, purchasedAt: daysAgo(0), store: "Beispiel-Einkauf"),
            Product(name: "Bananen", quantity: "1 kg", price: 1.76, category: .bananas, purchasedAt: daysAgo(0), store: "Beispiel-Einkauf")
        ]
        let total = products.reduce(0) { $0 + $1.price }
        purchases = [Purchase(store: "Beispiel-Einkauf", date: now, total: total, itemCount: products.count)]
        stores = [SavedStore(name: "Beispiel-Einkauf", colorHex: nil)]
        save()
    }
}
