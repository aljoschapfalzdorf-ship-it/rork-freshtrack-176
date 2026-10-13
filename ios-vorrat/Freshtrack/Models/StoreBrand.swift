import SwiftUI

/// A store slider the user has saved; products can be assigned to it.
nonisolated struct SavedStore: Identifiable, Codable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var colorHex: String?
}

/// Known German supermarket brands with their recognisable colours, matched
/// against the raw receipt text. Colours are data-driven accents on top of the
/// monochrome design (like the food photos).
nonisolated struct StoreBrand: Hashable, Sendable {
    let displayName: String
    let primaryHex: String
    let secondaryHex: String?
    let keywords: [String]

    var primary: Color? { Color(hex: primaryHex) }
    var secondary: Color? { secondaryHex.flatMap(Color.init(hex:)) }

    static let catalog: [StoreBrand] = [
        StoreBrand(displayName: "REWE", primaryHex: "#CC071E", secondaryHex: nil, keywords: ["rewe", "rewe markt"]),
        StoreBrand(displayName: "EDEKA", primaryHex: "#073B7A", secondaryHex: "#FFD500", keywords: ["edeka", "e-center", "neukauf", "handelshof"]),
        StoreBrand(displayName: "Netto", primaryHex: "#FFCC00", secondaryHex: "#E30613", keywords: ["netto marken", "netto-marken", "netto city", "schwarzes pferd"]),
        StoreBrand(displayName: "ALDI", primaryHex: "#23419F", secondaryHex: "#FFCC00", keywords: ["aldi", "aldi süd", "aldi sud", "aldi nord"]),
        StoreBrand(displayName: "Lidl", primaryHex: "#0050AA", secondaryHex: "#FFEC00", keywords: ["lidl"]),
        StoreBrand(displayName: "PENNY", primaryHex: "#E2001A", secondaryHex: nil, keywords: ["penny"]),
        StoreBrand(displayName: "Kaufland", primaryHex: "#E10918", secondaryHex: nil, keywords: ["kaufland"]),
        StoreBrand(displayName: "dm", primaryHex: "#05164D", secondaryHex: "#F39200", keywords: ["drogerie", "dm-drogerie", "dm drogerie"]),
        StoreBrand(displayName: "Rossmann", primaryHex: "#C80005", secondaryHex: nil, keywords: ["rossmann"]),
        StoreBrand(displayName: "Globus", primaryHex: "#00713A", secondaryHex: nil, keywords: ["globus"]),
        StoreBrand(displayName: "tegut", primaryHex: "#00793C", secondaryHex: nil, keywords: ["tegut"]),
        StoreBrand(displayName: "HIT", primaryHex: "#E30613", secondaryHex: nil, keywords: ["hit markt", "ismart", "famila"]),
        StoreBrand(displayName: "Norma", primaryHex: "#E66A00", secondaryHex: nil, keywords: ["norma"]),
        StoreBrand(displayName: "NP", primaryHex: "#E30613", secondaryHex: "#003D7B", keywords: ["np-discount", "np discount", "np-markt"]),
        StoreBrand(displayName: "Spar", primaryHex: "#007840", secondaryHex: nil, keywords: ["spar markt", "eurospar", "interspar"]),
        StoreBrand(displayName: "Denn's", primaryHex: "#78A22F", secondaryHex: nil, keywords: ["denn's", "denns biomarkt"])
    ]

    /// Findet die Marke im Bon-Text (Wortgrenzen, damit "hit" nicht in
    /// "Hitzefrei" passt). Reihenfolge des Katalogs gilt als Priorität.
    static func match(in text: String) -> StoreBrand? {
        for brand in catalog {
            for keyword in brand.keywords {
                let pattern = "\\b" + NSRegularExpression.escapedPattern(for: keyword) + "\\b"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
                let range = NSRange(location: 0, length: text.utf16.count)
                if regex.firstMatch(in: text, range: range) != nil {
                    return brand
                }
            }
        }
        return nil
    }
}

extension Color {
    /// "#RRGGBB" → Color.
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
