import Foundation

/// Grocery category used to pick a bundled product photo and an ingredient glyph.
nonisolated enum ProductCategory: String, Codable, CaseIterable, Sendable {
    case dairy, eggs, rice, tomatoes, bananas, vegetables, bread, cheese, pasta, fruit, meat, drinks, cereal, other

    var imageName: String {
        switch self {
        case .dairy: "yogurt_cup_spoon"
        case .eggs: "eggs_in_carton"
        case .rice: "rice_bag_bowl"
        case .tomatoes: "cherry_tomatoes_vine"
        case .bananas: "bananas_on_table"
        case .vegetables: "vegetables_on_table"
        case .bread: "sourdough_bread_rolls"
        case .cheese: "cheese_on_board"
        case .pasta: "pasta_jar_wooden_table"
        case .fruit: "fruit_bowl_wooden"
        case .meat: "raw_meat_herbs_table"
        case .drinks: "beverage_bottles_table"
        case .cereal: "oats_bowl_wooden_spoon"
        case .other: "grocery_bag_assorted"
        }
    }

    var symbol: String {
        switch self {
        case .dairy: "waterbottle"
        case .eggs: "oval.portrait"
        case .rice, .cereal: "takeoutbag.and.cup.and.straw"
        case .tomatoes, .fruit, .bananas: "apple.logo"
        case .vegetables: "leaf"
        case .bread: "birthday.cake"
        case .cheese: "triangle"
        case .pasta: "fork.knife"
        case .meat: "flame"
        case .drinks: "cup.and.saucer"
        case .other: "basket"
        }
    }

    /// Best-effort keyword guess for a German product or ingredient name.
    static func guess(from name: String) -> ProductCategory {
        let n = name.lowercased()
        let table: [(ProductCategory, [String])] = [
            (.eggs, ["ei ", "eier", "egg"]),
            (.cheese, ["käse", "kaese", "parmesan", "gouda", "mozzarella", "feta", "cheese"]),
            (.dairy, ["milch", "joghurt", "jogurt", "sahne", "quark", "butter", "skyr", "kefir", "milk", "yogurt"]),
            (.rice, ["reis", "rice"]),
            (.tomatoes, ["tomate", "tomato"]),
            (.bananas, ["banane", "banana"]),
            (.bread, ["brot", "brötchen", "toast", "baguette", "semmel", "bread"]),
            (.pasta, ["nudel", "pasta", "spaghetti", "penne", "fusilli", "lasagne"]),
            (.cereal, ["hafer", "müsli", "muesli", "cornflakes", "flocken", "oat"]),
            (.meat, ["hähnchen", "huhn", "rind", "schwein", "hack", "wurst", "schinken", "salami", "fleisch", "lachs", "fisch", "chicken", "beef"]),
            (.drinks, ["wasser", "saft", "cola", "limo", "bier", "wein", "tee", "kaffee", "sprudel", "drink"]),
            (.fruit, ["apfel", "äpfel", "birne", "orange", "zitrone", "beere", "traube", "kiwi", "mango", "obst"]),
            (.vegetables, ["brokkoli", "karotte", "möhre", "paprika", "gurke", "salat", "zwiebel", "kartoffel", "spinat", "zucchini", "knoblauch", "gemüse", "pilz", "champignon", "basilikum"])
        ]
        for (category, keywords) in table where keywords.contains(where: { n.contains($0) }) {
            return category
        }
        return .other
    }
}
