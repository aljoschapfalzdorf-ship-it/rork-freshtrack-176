import Foundation
import Observation
import StoreKit

/// Verwaltet das monatliche Vorrat-Pro-Abo (0,99 €) über StoreKit 2.
/// Der Kauf läuft über die Apple-ID-Zahlung (In-App-Purchase).
@Observable
final class ProManager {
    static let productID = "app.rork.fwa5bgudhsakfldvz720v.pro.monthly"
    private static let developerDefaultsKey = "developerProMode"

    /// Pro läuft, solange das StoreKit-Abo aktiv ist ODER der Developer-Modus an ist.
    var isPro: Bool { developerMode || storeEntitled }
    /// Freischaltung ohne Kauf über den Developer-Button in den Einstellungen.
    private(set) var developerMode: Bool
    private var storeEntitled: Bool = false
    private(set) var product: StoreKit.Product?
    private(set) var isPurchasing: Bool = false
    private(set) var errorMessage: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        developerMode = UserDefaults.standard.bool(forKey: Self.developerDefaultsKey)
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlement()
            }
        }
        Task {
            await refreshEntitlement()
            await loadProduct()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    /// Anzeige-Preis aus dem Store, mit Fallback vor der ersten Store-Antwort.
    var priceText: String {
        product?.displayPrice ?? "0,99 €"
    }

    @MainActor
    func loadProduct() async {
        do {
            product = try await StoreKit.Product.products(for: [Self.productID]).first
        } catch {
            print("Pro: Produktpreis konnte nicht geladen werden: \(error.localizedDescription)")
        }
    }

    @MainActor
    func refreshEntitlement() async {
        var entitled = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               transaction.productID == Self.productID {
                entitled = true
            }
        }
        storeEntitled = entitled
    }

    /// Schaltet Pro kostenlos frei (Developer-Modus) — zweiter Tipp
    /// nimmt die Freischaltung wieder zurück.
    func toggleDeveloperMode() {
        developerMode.toggle()
        UserDefaults.standard.set(developerMode, forKey: Self.developerDefaultsKey)
    }

    /// Setzt den Developer-Modus zurück (z. B. beim Löschen des Accounts).
    func resetDeveloperMode() {
        guard developerMode else { return }
        developerMode = false
        UserDefaults.standard.removeObject(forKey: Self.developerDefaultsKey)
    }

    /// Startet den Kauf. Gibt true zurück, sobald Pro aktiv ist.
    @discardableResult
    func purchase() async -> Bool {
        guard !isPurchasing else { return isPro }
        errorMessage = nil
        isPurchasing = true
        defer { isPurchasing = false }

        if product == nil { await loadProduct() }
        guard let product else {
            errorMessage = "Der App Store ist gerade nicht erreichbar. Bitte versuche es später erneut."
            return false
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlement()
                    return isPro
                }
                errorMessage = "Der Kauf konnte nicht bestätigt werden. Bitte versuche es erneut."
            case .userCancelled:
                break
            case .pending:
                errorMessage = "Der Kauf muss noch freigegeben werden (z. B. bei Familienteilung)."
            @unknown default:
                errorMessage = "Unbekannter Store-Status. Bitte versuche es erneut."
            }
        } catch {
            if isPro { return true }
            errorMessage = Self.purchaseErrorMessage(error)
        }
        return false
    }

    @discardableResult
    func restore() async -> Bool {
        do { try await AppStore.sync() } catch { }
        await refreshEntitlement()
        return isPro
    }

    private static func purchaseErrorMessage(_ error: Error) -> String {
        guard let storeError = error as? StoreKitError else {
            return "Der Kauf ist fehlgeschlagen. Bitte versuche es erneut."
        }
        switch storeError {
        case .networkError: return "Keine Verbindung zum App Store. Prüfe dein Internet."
        case .notAvailableInStorefront: return "Das Abo ist in deinem Land nicht verfügbar."
        default: return "Der Kauf ist fehlgeschlagen. Bitte versuche es erneut."
        }
    }
}
