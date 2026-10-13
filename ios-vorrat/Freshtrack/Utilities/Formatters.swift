import Foundation

nonisolated enum Formatters {
    static let german = Locale(identifier: "de_DE")

    static func euro(_ value: Double) -> String {
        value.formatted(.currency(code: "EUR").locale(german))
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(german))
    }

    static func longDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year().locale(german))
    }

    static func months(_ value: Int) -> String {
        value.formatted(.number.locale(german))
    }
}
