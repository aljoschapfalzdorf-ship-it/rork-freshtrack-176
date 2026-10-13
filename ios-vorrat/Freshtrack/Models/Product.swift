import Foundation

/// A grocery item currently stored at home.
nonisolated struct Product: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var quantity: String
    var price: Double
    var category: ProductCategory
    var purchasedAt: Date
    var store: String?
}

/// A scanned receipt, used for the monthly spending total.
nonisolated struct Purchase: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var store: String
    var date: Date
    var total: Double
    var itemCount: Int
}

/// A line item recognised on a receipt, before it is added to the pantry.
nonisolated struct ScannedItem: Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var quantity: String
    var price: Double
    var category: ProductCategory
    var isSelected: Bool = true
}

/// The structured result of reading a receipt photo.
nonisolated struct ScannedReceipt: Hashable, Sendable {
    var store: String
    var storeColorHex: String?
    var date: Date?
    var total: Double?
    var items: [ScannedItem]
}
