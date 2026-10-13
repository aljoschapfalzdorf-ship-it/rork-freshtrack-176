import Foundation

nonisolated struct RecipeIngredient: Identifiable, Codable, Hashable, Sendable {
    var id: String { name + amount }
    var name: String
    var amount: String
    var isAvailable: Bool
}

/// A recipe suggested by the AI chef.
nonisolated struct Recipe: Codable, Hashable, Sendable {
    var title: String
    var durationMinutes: Int?
    var servings: Int?
    var ingredients: [RecipeIngredient]
    var steps: [String]
    var imagePrompt: String
    var imageFileName: String?
    var imageFailed: Bool = false
}

nonisolated struct ChatMessage: Identifiable, Codable, Hashable, Sendable {
    nonisolated enum Role: String, Codable, Sendable {
        case user, assistant
    }

    var id: UUID = UUID()
    var role: Role
    var text: String
    var recipe: Recipe?
    var closing: String?
    var date: Date = .now
}
