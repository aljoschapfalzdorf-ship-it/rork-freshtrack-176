import Foundation
import UIKit

nonisolated enum AIError: LocalizedError, Equatable {
    case unavailable, noCredits, rateLimited, server, parse, imageTooLarge, notReceipt

    var errorDescription: String? {
        switch self {
        case .unavailable: "Die KI ist gerade nicht erreichbar. Bitte starte die App neu."
        case .noCredits: "Die KI ist vorübergehend nicht verfügbar. Bitte versuche es später erneut."
        case .rateLimited: "Zu viele Anfragen. Warte kurz und versuche es noch einmal."
        case .server: "Da ist etwas schiefgelaufen. Bitte versuche es erneut."
        case .parse: "Die Antwort konnte nicht gelesen werden. Bitte versuche es erneut."
        case .imageTooLarge: "Das Foto ist zu groß. Bitte versuche es mit einem anderen Bild."
        case .notReceipt: "Auf dem Foto wurde kein Kassenbon erkannt. Halte den Bon flach und gut beleuchtet in den Rahmen."
        }
    }
}

/// One turn of chat history sent to the AI chef.
nonisolated struct ChatTurn: Sendable {
    let role: String
    let content: String
}

/// Talks to the Google Gemini API (KI-Koch, via API key) and the Rork
/// Toolkit proxy (Vercel AI Gateway, OpenAI-compatible chat completions).
nonisolated enum AIService {
    static let textModels: [String] = ["google/gemini-3.8-flash", "google/gemini-3.5-flash-lite"]
    /// Modelle für den KI-Koch über die direkte Google Gemini API —
    /// schnellstes Modell zuerst (Flash-Lite), dann Flash als Fallback.
    static let geminiModels: [String] = ["gemini-flash-lite-latest", "gemini-flash-latest"]

    // MARK: Receipt

    /// Reads a receipt photo and returns recognised line items.
    static func parseReceipt(image: UIImage) async throws -> ScannedReceipt {
        guard let jpeg = compressForUpload(image) else { throw AIError.imageTooLarge }
        let prompt = """
        Du liest einen deutschen Kassenbon (Supermarkt, Drogerie, Bäcker …) von einem Foto.
        Antworte AUSSCHLIESSLICH mit einem JSON-Objekt, ohne Erklärungen, ohne Markdown:
        {"isReceipt": true, "store": "REWE", "date": "YYYY-MM-DD", "total": 13.44,
         "items": [{"name": "Vollmilch 3,8%", "quantity": "1 l", "price": 1.19, "category": "dairy"}]}
        Regeln:
        - name: gut lesbarer deutscher Produktname, Abkürzungen ausschreiben (z. B. "BIO EIER 10ER" → "Bio-Eier 10er").
        - quantity: Menge/Größe wenn erkennbar (z. B. "1 l", "500 g", "10 Stück", "2 ×"), sonst "1 Stück".
        - price: Endpreis der Zeile in Euro als Zahl.
        - Pfand, Leergut, Rabatte, Tüten, Summenzeilen und Zahlungsinfos NICHT als Artikel aufnehmen.
        - category: genau einer von dairy, eggs, rice, tomatoes, bananas, vegetables, bread, cheese, pasta, fruit, meat, drinks, cereal, other.
        - total: Gesamtsumme des Bons. date: Kaufdatum oder null.
        - Wenn das Bild kein Kassenbon ist: {"isReceipt": false, "items": []}.
        """
        let messages: [[String: Any]] = [[
            "role": "user",
            "content": [
                ["type": "text", "text": prompt],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"]]
            ]
        ]]
        let raw = try await completeText(messages: messages)
        guard let data = extractJSON(raw) else { throw AIError.parse }
        let dto: ReceiptDTO
        do { dto = try JSONDecoder().decode(ReceiptDTO.self, from: data) } catch { throw AIError.parse }
        if dto.isReceipt == false || dto.items.isEmpty { throw AIError.notReceipt }

        let items: [ScannedItem] = dto.items.compactMap { item in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let category = item.category.flatMap { ProductCategory(rawValue: $0) } ?? ProductCategory.guess(from: name)
            return ScannedItem(name: name, quantity: item.quantity ?? "1 Stück", price: item.price ?? 0, category: category)
        }
        guard !items.isEmpty else { throw AIError.notReceipt }
        return ScannedReceipt(store: dto.store ?? "Einkauf", date: parseDate(dto.date), total: dto.total, items: items)
    }

    // MARK: Chef

    static func chef(history: [ChatTurn], pantry: [String]) async throws -> ChefReply {
        let pantryText = pantry.isEmpty ? "(Der Freshtrack ist gerade leer.)" : pantry.map { "- \($0)" }.joined(separator: "\n")
        let system = """
        Du bist "KI-Koch" in der App Freshtrack – ein herzlicher, präziser Kochassistent. Du sprichst Deutsch und duzt.
        Das hat der Nutzer aktuell zu Hause (aus seinen gescannten Kassenbons):
        \(pantryText)

        Antworte AUSSCHLIESSLICH mit einem JSON-Objekt, ohne Markdown:
        {"message": "kurzer Einleitungstext (1–3 Sätze)",
         "recipe": null ODER {"title": "…", "durationMinutes": 25, "servings": 2,
            "ingredients": [{"name": "Basmati Reis", "amount": "200 g", "available": true}],
            "steps": ["…", "…"]},
         "closing": "kurzer Abschlusssatz oder null"}
        Regeln:
        - Fragt der Nutzer, was er kochen kann, oder nach einem Gericht/Rezept: liefere GENAU ein Rezept, das möglichst viele vorhandene Produkte nutzt.
        - available = true, wenn die Zutat im Freshtrack ist. Salz, Pfeffer, Öl, Wasser und Zucker gelten als vorhanden. Fehlende Zutaten mit available = false (höchstens 3).
        - steps: 3–8 klare, konkrete Schritte mit Zeiten/Temperaturen, jeder Schritt ein Satz.
        - Für andere Fragen (z. B. was noch da ist, Haltbarkeit, Einkaufsliste) antworte nur mit message und recipe = null.
        """
        var messages: [[String: Any]] = [["role": "system", "content": system]]
        for turn in history {
            messages.append(["role": turn.role, "content": turn.content])
        }
        // KI-Koch läuft über den Google API-Key; ohne Key greift der
        // bisherige Gateway-Fallback.
        let raw = try await geminiComplete(system: system, history: history, fallbackMessages: messages)
        guard let data = extractJSON(raw) else {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw AIError.parse }
            return ChefReply(message: text, recipe: nil, closing: nil)
        }
        do {
            let dto = try JSONDecoder().decode(ChefDTO.self, from: data)
            let recipe: Recipe? = dto.recipe.map { r in
                Recipe(
                    title: r.title,
                    durationMinutes: r.durationMinutes,
                    servings: r.servings,
                    ingredients: r.ingredients.map { RecipeIngredient(name: $0.name, amount: $0.amount ?? "", isAvailable: $0.available ?? false) },
                    steps: r.steps,
                    imagePrompt: r.title
                )
            }
            return ChefReply(message: dto.message ?? "", recipe: recipe, closing: dto.closing)
        } catch {
            throw AIError.parse
        }
    }

    // MARK: Gemini (KI-Koch)

    /// KI-Koch-Antwort über die direkte Google Gemini API (API-Key aus der
    /// Build-Konfiguration). Ohne konfigurierten Key: Fallback auf den
    /// bisherigen Gateway (OpenAI-kompatibel).
    private static func geminiComplete(system: String, history: [ChatTurn], fallbackMessages: [[String: Any]]) async throws -> String {
        // Zugriff über allValues, damit der Build auch vor der ersten
        // Config-Regenerierung kompiliert (leer = Gateway-Fallback).
        let apiKey = Config.allValues["EXPO_PUBLIC_GOOGLE_AI_API_KEY"] ?? ""
        guard !apiKey.isEmpty else {
            return try await completeText(messages: fallbackMessages)
        }
        let contents: [[String: Any]] = history.map { turn in
            ["role": turn.role == "assistant" ? "model" : "user",
             "parts": [["text": turn.content]]]
        }
        var lastError: Error = AIError.server
        for model in geminiModels {
            // Hinweis: thinkingConfig wird von flash-lite(-latest) mit
            // 400 INVALID_ARGUMENT abgelehnt — deshalb kein thinkingBudget.
            let body: [String: Any] = [
                "systemInstruction": ["parts": [["text": system]]],
                "contents": contents,
                "generationConfig": ["temperature": 0.7]
            ]
            do {
                let data = try await postGemini(body, model: model, apiKey: apiKey, timeout: 90)
                let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
                let text = decoded.candidates?.first?.content?.parts?.compactMap { $0.text ?? "" }
                    .joined(separator: "\n")
                if let text, !text.isEmpty { return text }
                lastError = AIError.parse
            } catch let error as AIError where error == .rateLimited {
                throw error
            } catch let error as AIError where error == .unavailable {
                // Key abgelehnt oder Anfrage nicht akzeptiert →
                // sauber auf den Gateway ausweichen statt Fehler zu zeigen.
                return try await completeText(messages: fallbackMessages)
            } catch {
                lastError = error
            }
        }
        if lastError is AIError { throw lastError }
        throw AIError.server
    }

    private static func postGemini(_ body: [String: Any], model: String, apiKey: String, timeout: TimeInterval) async throws -> Data {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw AIError.unavailable
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: return data
        case 400, 401, 403:
            // 400 meist „API key not valid“ → als Auth-Fehler behandeln,
            // damit der Aufrufer auf den Gateway ausweichen kann.
            if let body = String(data: data.prefix(300), encoding: .utf8), !body.isEmpty {
                print("Gemini request rejected (\(status)): \(body)")
            }
            throw AIError.unavailable
        case 429: throw AIError.rateLimited
        default:
            print("Gemini request failed with status \(status)")
            throw AIError.server
        }
    }

    // MARK: Networking

    private static func completeText(messages: [[String: Any]]) async throws -> String {
        var lastError: Error = AIError.server
        for model in textModels {
            let body: [String: Any] = ["model": model, "messages": messages]
            do {
                let data = try await post(body, timeout: 90)
                let decoded = try JSONDecoder().decode(CompletionResponse.self, from: data)
                if let content = decoded.choices.first?.message.content, !content.isEmpty {
                    return content
                }
                lastError = AIError.parse
            } catch let error as AIError where error == .noCredits || error == .unavailable || error == .imageTooLarge {
                throw error
            } catch {
                lastError = error
            }
        }
        if lastError is AIError { throw lastError }
        throw AIError.server
    }

    private static func post(_ body: [String: Any], timeout: TimeInterval) async throws -> Data {
        guard !Config.EXPO_PUBLIC_TOOLKIT_URL.isEmpty,
              let url = URL(string: "\(Config.EXPO_PUBLIC_TOOLKIT_URL)/v2/vercel/v1/chat/completions") else {
            throw AIError.unavailable
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Config.EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: return data
        case 401, 403: throw AIError.unavailable
        case 402: throw AIError.noCredits
        case 413: throw AIError.imageTooLarge
        case 429: throw AIError.rateLimited
        default:
            print("AI request failed with status \(status)")
            throw AIError.server
        }
    }

    // MARK: Helpers

    /// Downscales and re-encodes an image to stay well below the gateway body limit.
    static func compressForUpload(_ image: UIImage, maxBytes: Int = 2_800_000) -> Data? {
        let ladder: [(CGFloat, CGFloat)] = [(1600, 0.8), (1280, 0.78), (1024, 0.74), (832, 0.7), (640, 0.65)]
        for (edge, quality) in ladder {
            let resized = resize(image, maxEdge: edge)
            if let data = resized.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return data
            }
        }
        return nil
    }

    private static func resize(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxEdge else { return image }
        let scale = maxEdge / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    private static func extractJSON(_ text: String) -> Data? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return String(text[start...end]).data(using: .utf8)
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: value) else { return nil }
        let now = Date.now
        guard date <= now, date > now.addingTimeInterval(-60 * 60 * 24 * 365) else { return nil }
        return date
    }
}

nonisolated struct ChefReply: Sendable {
    let message: String
    let recipe: Recipe?
    let closing: String?
}

// MARK: DTOs

private nonisolated struct CompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
    }
    let choices: [Choice]
}

private nonisolated struct GeminiResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable { let text: String? }
            let parts: [Part]?
        }
        let content: Content?
    }
    let candidates: [Candidate]?
}

private nonisolated struct ReceiptDTO: Decodable {
    let isReceipt: Bool?
    let store: String?
    let date: String?
    let total: Double?
    let items: [ItemDTO]

    enum CodingKeys: String, CodingKey { case isReceipt, store, date, total, items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isReceipt = try? c.decode(Bool.self, forKey: .isReceipt)
        store = try? c.decode(String.self, forKey: .store)
        date = try? c.decode(String.self, forKey: .date)
        total = FlexibleNumber.decode(c, .total)
        items = (try? c.decode([ItemDTO].self, forKey: .items)) ?? []
    }
}

private nonisolated struct ItemDTO: Decodable {
    let name: String
    let quantity: String?
    let price: Double?
    let category: String?

    enum CodingKeys: String, CodingKey { case name, quantity, price, category }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        quantity = try? c.decode(String.self, forKey: .quantity)
        price = FlexibleNumber.decode(c, .price)
        category = try? c.decode(String.self, forKey: .category)
    }
}

private nonisolated enum FlexibleNumber {
    static func decode<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Double? {
        if let d = try? c.decode(Double.self, forKey: key) { return d }
        if let s = try? c.decode(String.self, forKey: key) {
            let cleaned = s.replacingOccurrences(of: "€", with: "")
                .replacingOccurrences(of: ",", with: ".")
                .trimmingCharacters(in: .whitespaces)
            return Double(cleaned)
        }
        return nil
    }
}

private nonisolated struct ChefDTO: Decodable {
    let message: String?
    let recipe: RecipeDTO?
    let closing: String?
}

private nonisolated struct RecipeDTO: Decodable {
    let title: String
    let durationMinutes: Int?
    let servings: Int?
    let ingredients: [IngredientDTO]
    let steps: [String]
}

private nonisolated struct IngredientDTO: Decodable {
    let name: String
    let amount: String?
    let available: Bool?
}
