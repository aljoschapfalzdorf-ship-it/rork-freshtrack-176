import Foundation
import UserNotifications

/// Sendet eine lokale Mitteilung, sobald im laufenden Monat 80 % des
/// Monatsbudgets erreicht sind. Erinnert pro Monat höchstens einmal.
nonisolated final class BudgetNotificationService {
    static let shared = BudgetNotificationService()

    private let threshold: Double = 0.8
    private let monthKey = "budgetNotificationMonth"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Erlaubnis für lokale Mitteilungen anfragen (idempotent).
    func requestAuthorization() {
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        }
    }

    /// Prüft nach jeder Änderung, ob die 80-%-Marke in diesem Monat
    /// neu erreicht wurde – dann kommt die Mitteilung.
    func check(monthSpent: Double, budget: Double) {
        guard budget > 0 else { return }
        guard monthSpent / budget >= threshold else { return }

        let month = Self.currentMonthKey()
        guard defaults.string(forKey: monthKey) != month else { return }
        defaults.set(month, forKey: monthKey)

        let percent = Int((monthSpent / budget * 100).rounded())
        let content = UNMutableNotificationContent()
        content.title = "Fast am Limit"
        content.body = "Du hast \(Formatters.euro(monthSpent)) von \(Formatters.euro(budget)) ausgegeben – das sind \(percent) % deines Monatsbudgets."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "budget.80.\(month)",
            content: content,
            trigger: nil // sofort zustellen
        )
        UNUserNotificationCenter.current().add(request)
    }

    private static func currentMonthKey() -> String {
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: .now)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }
}
