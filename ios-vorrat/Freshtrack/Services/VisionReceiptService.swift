import Foundation
import UIKit
import Vision
import CoreImage

/// Liest Kassenbons vollständig auf dem Gerät mit dem Apple Vision Framework –
/// ohne KI-Modell und ohne Netzwerk.
///
/// Für eine hohe Trefferquote arbeiten drei Ebenen zusammen:
/// 1. Bildvorverarbeitung (Hochskalieren, Graustufen, Kontrast, Schärfen)
/// 2. Zwei Erkennungsläufe (mit und ohne Sprachkorrektur) und Zusammenführung
/// 3. Zeilen-Klassifikator: jede Zeile wird zuerst als Kopf, Produkt,
///    Summe/Netto, Zahlung oder Fußzeile eingestuft – nur Produktzeilen
///    werden geparst (Produktname zuerst, Preis dahinter).
nonisolated enum VisionReceiptService {
    static func parseReceipt(image: UIImage) async throws -> ScannedReceipt {
        let lines = try await recognizeLines(in: image)
        let receipt = ReceiptTextParser.receipt(from: lines)
        guard !receipt.items.isEmpty else { throw AIError.notReceipt }
        return receipt
    }

    // MARK: OCR

    private static func recognizeLines(in image: UIImage) async throws -> [OCRLine] {
        try await Task.detached(priority: .userInitiated) {
            guard let original = image.cgImage else { throw AIError.parse }
            let cgImage = preprocess(original) ?? original
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            func run(languageCorrection: Bool) -> [VNRecognizedTextObservation] {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = languageCorrection
                request.recognitionLanguages = ["de-DE", "en-US"]
                do { try handler.perform([request]) } catch { return [] }
                return (request.results as? [VNRecognizedTextObservation]) ?? []
            }

            // Lauf 1 mit Sprachkorrektur (sinnvolle Wörter), Lauf 2 ohne
            // (Artikelnummern und Codes leiden sonst unter der Korrektur).
            return mergeRows(primary: run(languageCorrection: true), secondary: run(languageCorrection: false))
        }.value
    }

    /// Graustufen + mehr Kontrast + Schärfen + Hochskalieren, damit die kleine
    /// Bon-Schrift sicher erkannt wird. Gibt das Original zurück, wenn CoreImage
    /// fehlschlägt – der Scan funktioniert dann trotzdem.
    private static func preprocess(_ cgImage: CGImage) -> CGImage? {
        var ciImage = CIImage(cgImage: cgImage)
        let targetWidth: CGFloat = 1600
        let width = ciImage.extent.width
        if width > 0, width < targetWidth {
            let scale = min(3, targetWidth / width)
            ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        guard let contrast = CIFilter(name: "CIColorControls") else { return nil }
        contrast.setValue(ciImage, forKey: kCIInputImageKey)
        contrast.setValue(0.0, forKey: kCIInputSaturationKey)
        contrast.setValue(1.25, forKey: kCIInputContrastKey)
        contrast.setValue(0.02, forKey: kCIInputBrightnessKey)
        var output = contrast.outputImage ?? ciImage
        if let sharpen = CIFilter(name: "CISharpenLuminance") {
            sharpen.setValue(output, forKey: kCIInputImageKey)
            sharpen.setValue(0.7, forKey: "inputSharpness")
            output = sharpen.outputImage ?? output
        }
        let context = CIContext()
        return context.createCGImage(output, from: output.extent)
    }

    /// Führt beide Erkennungsläufe zusammen: Fragmente derselben Zeile werden
    /// zu einer Zeile verbunden (Name links, Preis rechts), Dubletten übersprungen.
    private static func mergeRows(primary: [VNRecognizedTextObservation], secondary: [VNRecognizedTextObservation]) -> [OCRLine] {
        var rows: [(midY: CGFloat, fragments: [(CGRect, String)])] = []

        func insert(box: CGRect, text: String) {
            let tolerance = max(box.height, 0.015) * 0.8
            if let index = rows.firstIndex(where: { abs($0.midY - box.midY) < tolerance }) {
                rows[index].fragments.append((box, text))
            } else {
                rows.append((box.midY, [(box, text)]))
            }
        }

        for observation in primary {
            guard let candidate = observation.topCandidates(1).first else { continue }
            insert(box: observation.boundingBox, text: candidate.string)
        }
        for observation in secondary {
            guard let candidate = observation.topCandidates(1).first else { continue }
            insert(box: observation.boundingBox, text: candidate.string)
        }

        return rows.compactMap { row -> OCRLine? in
            var kept: [(CGRect, String)] = []
            for fragment in row.fragments.sorted(by: { $0.0.minX < $1.0.minX }) {
                // Gleiches Fragment aus beiden Läufen nur einmal übernehmen.
                if let previous = kept.last, horizontalOverlap(fragment.0, previous.0) > 0.5 { continue }
                kept.append(fragment)
            }
            guard let first = kept.first else { return nil }
            let text = kept.map(\.1).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            let box = kept.dropFirst().reduce(first.0) { $0.union($1.0) }
            return OCRLine(text: text, box: box)
        }
        .sorted { $0.box.midY > $1.box.midY }
    }

    /// Überlappung der Breite relativ zum schmaleren Fragment (0…1).
    private static func horizontalOverlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull, intersection.width > 0 else { return 0 }
        let smaller = min(a.width, b.width)
        guard smaller > 0 else { return 0 }
        return intersection.width / smaller
    }
}

/// Eine erkannte Textzeile mit ihrer Position im Bild.
nonisolated struct OCRLine: Sendable {
    let text: String
    let box: CGRect
}

// MARK: - Zeilen-Klassifikator + Parser

/// Rein lokaler Parser: stuft jede Zeile zuerst ein und baut aus echten
/// Produktzeilen (Name vorne, Preis hinten) Store, Datum, Summe und Artikel.
nonisolated enum ReceiptTextParser {
    private enum LineKind {
        case header, summary, payment, footer, product, noise
    }

    // Kurze Begriffe zählen nur als ganzes Wort – "bar" soll "Barilla" nicht treffen.
    private static let summaryWords: Set<String> = [
        "summe", "gesamt", "total", "netto", "brutto", "umsatz", "mwst", "mst", "ust",
        "steuer", "steuern", "saldo", "warenwert", "verkauf", "kassenbericht", "schnitt",
        "ergebnis", "betrag", "steuerbetrag", "vat", "tax"
    ]
    private static let summaryPhrases = [
        "zu zahlen", "zu bezahlen", "zwischensumme", "summe eur", "total eur",
        "brutto-betrag", "netto-betrag", "gesamtersparnis", "sie sparen", "ersparnis",
        "verkaufsergebnis", "umsatz netto"
    ]
    private static let paymentWords: Set<String> = [
        "bar", "karte", "kredit", "debit", "visa", "mastercard", "girocard", "sepa",
        "contactless", "pfand", "leergut", "rabatt", "gutschein", "coupon", "storno",
        "gegeben", "gezahl", "auflad", "guthaben"
    ]
    private static let paymentPhrases = [
        "barzahlung", "kartenzahlung", "rückgeld", "rueckgeld", "wechselgeld",
        "kontaktlos", "kartenzahl", "belastung", "abbuchung", "authorisiert", "autorisiert"
    ]
    private static let footerPhrases = [
        "danke", "viele grüße", "öffnungszeiten", "www.", "http", "tel.", "telefon",
        "widerruf", "umtausch", "rückgabe", "rueckgabe", "garantie", "hinweis",
        "aufsicht", "leitung", "seite", "folio", "omr", "bonkopie", "nachweis"
    ]
    private static let headerPhrases = [
        "kassenbon", "kassenbeleg", "beleg", "filiale", "willkommen", "rechnung",
        "bon-nr", "bonid", "bonnr", "datum", "uhrzeit", "kasse ", "kasse:", "terminal"
    ]

    /// Preise inkl. häufiger OCR-Verwechslungen: l/I statt 1, o/O statt 0.
    private static let priceRegex = try? NSRegularExpression(pattern: #"([\dlIoO]{1,4})[.,]([\dlIoO]{2})(?!\d)"#)
    private static let dateRegex = try? NSRegularExpression(pattern: #"(\d{1,2})[.,\-/](\d{1,2})[.,\-/](\d{2}|\d{4})"#)
    private static let timeRegex = try? NSRegularExpression(pattern: #"\b\d{1,2}:\d{2}\b"#)
    private static let longNumberRegex = try? NSRegularExpression(pattern: #"\d{6,}"#)
    private static let weightRegex = try? NSRegularExpression(pattern: #"(\d+[.,]?\d*)\s*(kg|g|l|ml|stk|st|stück)\b"#, options: [.caseInsensitive])
    private static let leadingCountRegex = try? NSRegularExpression(pattern: #"^(\d{1,2})\s*[x×]\s+"#, options: [.caseInsensitive])
    private static let trailingFlagRegex = try? NSRegularExpression(pattern: #"\s+[A-Ea-e]$"#)

    private static let strongTotalWords = ["summe", "gesamt", "total", "zu zahlen", "zu bezahlen", "saldo"]

    static func receipt(from lines: [OCRLine]) -> ScannedReceipt {
        // Bild-Koordinaten laufen von unten nach oben – sortiere von oben (Kopf) nach unten (Fuß).
        let texts = lines.sorted { $0.box.midY > $1.box.midY }.map(\.text)
        let kinds = texts.enumerated().map { classify($0.element, index: $0.offset, count: texts.count) }
        // Bekannte Marke in irgendeiner Bon-Zeile schlägt die freie Kopfzeilen-Erkennung.
        let brand = StoreBrand.match(in: texts.joined(separator: "\n"))
        let storeName = brand?.displayName ?? detectStore(in: texts)
        return ScannedReceipt(
            store: storeName,
            storeColorHex: brand?.primaryHex,
            date: detectDate(in: texts),
            total: detectTotal(in: texts, kinds: kinds),
            items: detectItems(in: texts, kinds: kinds)
        )
    }

    // MARK: Klassifikation

    private static func classify(_ text: String, index: Int, count: Int) -> LineKind {
        let lower = text.lowercased()

        if matchesAny(uppercased: lower, phrases: summaryPhrases) || matchesWord(lower: lower, words: summaryWords) {
            return .summary
        }
        if matchesAny(uppercased: lower, phrases: paymentPhrases) || matchesWord(lower: lower, words: paymentWords) {
            return .payment
        }
        if matchesAny(uppercased: lower, phrases: footerPhrases) {
            return .footer
        }
        if index < 3, matchesAny(uppercased: lower, phrases: headerPhrases) {
            return .header
        }

        let hasPrice = priceRange(in: text) != nil
        let letters = text.filter(\.isLetter).count
        if hasPrice, letters >= 2, dateRange(in: text) == nil,
           timeRange(in: text) == nil, longNumberRange(in: text) == nil {
            // Prozent-/Steuerzeilen wie "19.0% B 1.23" sind keine Produkte.
            if lower.contains("%") && letters < 4 { return .summary }
            return .product
        }
        return .noise
    }

    /// Ganze-Phrase-Abgleich (auch über Satzzeichen hinweg).
    private static func matchesAny(uppercased lower: String, phrases: [String]) -> Bool {
        phrases.contains { lower.contains($0) }
    }

    /// Kurze Schlüsselwörter nur als eigenes Wort am Zeilenanfang/nach Leerzeichen.
    private static func matchesWord(lower: String, words: Set<String>) -> Bool {
        let tokens = lower.split(whereSeparator: { $0 == " " || $0 == "\t" })
        return tokens.contains { token in
            let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:-–*%€0123456789()[]"))
            return words.contains(trimmed)
        }
    }

    // MARK: Store

    private static func detectStore(in texts: [String]) -> String {
        for text in texts.prefix(4) {
            let lower = text.lowercased()
            if matchesAny(uppercased: lower, phrases: footerPhrases) { continue }
            let letters = text.filter(\.isLetter)
            let digits = text.filter(\.isNumber)
            if letters.count >= 3, digits.count * 2 < letters.count,
               priceRange(in: text) == nil, dateRange(in: text) == nil {
                let cleaned = text.trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty { return cleaned }
            }
        }
        return "Einkauf"
    }

    // MARK: Date

    private static func detectDate(in texts: [String]) -> Date? {
        for text in texts {
            guard let range = dateRange(in: text) else { continue }
            let match = String(text[range])
            let parts = match.components(separatedBy: CharacterSet(charactersIn: ".,-/:"))
            guard parts.count >= 3,
                  let day = Int(parts[0]), day >= 1, day <= 31,
                  let month = Int(parts[1]), month >= 1, month <= 12 else { continue }
            var year = Int(parts[2]) ?? 0
            if year < 100 { year += 2000 }
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            let cal = Calendar(identifier: .gregorian)
            guard let date = cal.date(from: components), date <= Date.now,
                  date > Date.now.addingTimeInterval(-60 * 60 * 24 * 365) else { continue }
            return date
        }
        return nil
    }

    // MARK: Total

    private static func detectTotal(in texts: [String], kinds: [LineKind]) -> Double? {
        // 1. Summen-/Gesamtzeilen von unten nach oben – "Zwischensumme" zählt nicht.
        for (index, text) in texts.reversed().enumerated() {
            let kindIndex = texts.count - 1 - index
            guard kinds[kindIndex] == .summary else { continue }
            let lower = text.lowercased()
            guard lower.contains("zwischen") == false,
                  lower.contains("erspar") == false, lower.contains("gespart") == false,
                  strongTotalWords.contains(where: { lower.contains($0) }),
                  let range = priceRange(in: text) else { continue }
            let price = normalizedPrice(String(text[range]))
            if price > 0 { return price }
        }
        // 2. Fallback: der größte erkannte Preis auf dem Bon.
        return texts.compactMap { text -> Double? in
            guard let range = priceRange(in: text) else { return nil }
            let price = normalizedPrice(String(text[range]))
            return price > 0 && price < 1000 ? price : nil
        }.max()
    }

    // MARK: Items

    private static func detectItems(in texts: [String], kinds: [LineKind]) -> [ScannedItem] {
        // Erst Namen ohne Preis mit der nächsten reinen Preiszeile verbinden
        // ("MILCH" / "1,19 A" stehen in der OCR oft in getrennten Zeilen).
        var merged: [(String, LineKind)] = []
        var index = 0
        while index < texts.count {
            let (text, kind) = (texts[index], kinds[index])
            if priceRange(in: text) != nil {
                merged.append((text, kind))
                index += 1
            } else if kind == .product || kind == .noise, looksLikeName(text),
                      index + 1 < texts.count, isPriceOnly(texts[index + 1]) {
                // Beide Teile sind geprüft – gemeinsam ist es eine echte Produktzeile.
                merged.append((text + " " + texts[index + 1], .product))
                index += 2
            } else {
                merged.append((text, kind))
                index += 1
            }
        }

        var items: [ScannedItem] = []
        for (text, kind) in merged {
            guard kind == .product, let range = priceRange(in: text) else { continue }
            let price = normalizedPrice(String(text[range]))
            guard price > 0, price < 1000 else { continue }

            // Preis muss hinten stehen: dahinter sind höchstens 2 Buchstaben (Bon-Flag "A").
            let trailing = text[range.upperBound...].filter(\.isLetter).count
            guard trailing <= 2 else { continue }

            var name = String(text[..<(range.lowerBound)])
            // Zweite Preisangabe (Einzelpreis statt Hauptpreis) aus dem Namen entfernen.
            if let second = priceRange(in: name) { name = String(name[..<(second.lowerBound)]) }
            // Mengenannotationen wie "2 @ 1,19" oder "2STK @ 0,89" abschneiden.
            if let at = name.range(of: "@") { name = String(name[..<at.lowerBound]) }
            name = removeTrailingFlag(name)
            name = name.replacingOccurrences(of: "€", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.filter(\.isLetter).count >= 2 else { continue }

            var quantity = "1 Stück"
            if let match = leadingCountRegex?.firstMatch(in: name, range: NSRange(location: 0, length: name.count)) {
                let count = (name as NSString).substring(with: match.range(at: 1))
                quantity = "\(count) ×"
                name = (name as NSString).replacingCharacters(in: match.range, with: "")
            }
            if let match = weightRegex?.firstMatch(in: name, range: NSRange(location: 0, length: name.count)) {
                let value = (name as NSString).substring(with: match.range(at: 1))
                var unit = (name as NSString).substring(with: match.range(at: 2)).lowercased()
                if unit == "st" || unit == "stk" || unit == "stück" { unit = "Stück" }
                quantity = "\(value) \(unit)"
                name = (name as NSString).replacingCharacters(in: match.range, with: "")
            }

            let cleaned = tidy(name)
            guard !cleaned.isEmpty else { continue }
            items.append(ScannedItem(name: cleaned, quantity: quantity, price: price, category: ProductCategory.guess(from: cleaned)))
        }
        return items
    }

    /// Namenszeile ohne Preis: echte Buchstaben, keine Summen-/Zahlungszeile.
    private static func looksLikeName(_ text: String) -> Bool {
        let lower = text.lowercased()
        guard text.filter(\.isLetter).count >= 2 else { return false }
        if matchesAny(uppercased: lower, phrases: summaryPhrases) || matchesWord(lower: lower, words: summaryWords) { return false }
        if matchesAny(uppercased: lower, phrases: paymentPhrases) || matchesWord(lower: lower, words: paymentWords) { return false }
        if matchesAny(uppercased: lower, phrases: footerPhrases) { return false }
        return dateRange(in: text) == nil
    }

    /// Eine Zeile, die im Kern nur aus einem Preis besteht (plus Flags wie "A").
    private static func isPriceOnly(_ text: String) -> Bool {
        guard let range = priceRange(in: text) else { return false }
        let remainder = String(text[..<(range.lowerBound)]) + String(text[range.upperBound...])
        return remainder.filter(\.isLetter).count <= 2
    }

    /// Kapitalisieren und Leerzeichen aufräumen ("BIO EIER  10ER A" → "Bio Eier 10er").
    private static func tidy(_ raw: String) -> String {
        let collapsed = raw.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        guard !collapsed.isEmpty else { return "" }
        return collapsed.split(separator: " ").map { word in
            word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    // MARK: Regex helpers

    private static func priceRange(in text: String) -> Range<String.Index>? {
        guard let regex = priceRegex else { return nil }
        let nsRange = NSRange(location: 0, length: text.utf16.count)
        let matches = regex.matches(in: text, range: nsRange)
        guard let last = matches.last else { return nil }
        return Range(last.range, in: text)
    }

    private static func dateRange(in text: String) -> Range<String.Index>? {
        guard let regex = dateRegex else { return nil }
        let nsRange = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, range: nsRange) else { return nil }
        return Range(match.range, in: text)
    }

    private static func timeRange(in text: String) -> Range<String.Index>? {
        guard let regex = timeRegex else { return nil }
        let nsRange = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, range: nsRange) else { return nil }
        return Range(match.range, in: text)
    }

    private static func longNumberRange(in text: String) -> Range<String.Index>? {
        guard let regex = longNumberRegex else { return nil }
        let nsRange = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, range: nsRange) else { return nil }
        return Range(match.range, in: text)
    }

    /// OCR-Verwechslungen in Preisen korrigieren: l/i → 1, o → 0, Komma → Punkt.
    private static func normalizedPrice(_ raw: String) -> Double {
        let fixed = raw.lowercased()
            .replacingOccurrences(of: "l", with: "1")
            .replacingOccurrences(of: "i", with: "1")
            .replacingOccurrences(of: "o", with: "0")
            .replacingOccurrences(of: ",", with: ".")
        return Double(fixed) ?? 0
    }

    private static func removeTrailingFlag(_ text: String) -> String {
        guard let regex = trailingFlagRegex else { return text }
        let nsRange = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, range: nsRange), match.range.length > 0 else { return text }
        return (text as NSString).replacingCharacters(in: match.range, with: "")
    }
}
