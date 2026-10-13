import SwiftUI

/// Monthly spending breakdown, budget and life-estimate settings.
struct MonthOverviewSheet: View {
    @Environment(PantryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Formatters.euro(store.monthSpent))
                            .font(.system(size: 40, weight: .bold))
                            .monospacedDigit()
                        Text("von \(Formatters.euro(store.monthlyBudget)) Budget · \(Int((store.budgetProgress * 100).rounded())) %")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondary)
                        Text(store.daysUntilReset == 1 ? "Setzt sich morgen automatisch zurück." : "Setzt sich in \(store.daysUntilReset) Tagen automatisch zurück.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section("Einkäufe im \(store.currentMonthName)") {
                    if store.purchasesThisMonth.isEmpty {
                        Text("Noch keine Kassenbons in diesem Monat.")
                            .foregroundStyle(Theme.secondary)
                    }
                    ForEach(store.purchasesThisMonth) { purchase in
                        PurchaseRow(purchase: purchase)
                            .swipeActions {
                                Button("Löschen", systemImage: "trash", role: .destructive) {
                                    withAnimation { store.deletePurchase(purchase) }
                                }
                            }
                    }
                }

                Section {
                    Stepper(value: $store.monthlyBudget, in: 50...5000, step: 25) {
                        HStack {
                            Text("Monatsbudget")
                            Spacer()
                            Text(Formatters.euro(store.monthlyBudget))
                                .monospacedDigit()
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                } header: {
                    Text("Budget")
                } footer: {
                    Text("Bestimmt, wie voll der Balken auf der Startseite ist.")
                }

                Section {
                    DatePicker(
                        "Geburtstag",
                        selection: Binding(
                            get: { store.birthDate ?? defaultBirthDate },
                            set: { store.birthDate = $0 }
                        ),
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                    .environment(\.locale, Formatters.german)
                    Stepper(value: $store.lifeExpectancyYears, in: 50...110) {
                        HStack {
                            Text("Lebenserwartung")
                            Spacer()
                            Text("\(store.lifeExpectancyYears) Jahre")
                                .monospacedDigit()
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                    HStack {
                        Text("Verbleibend")
                        Spacer()
                        Text("\(Formatters.months(store.monthsRemaining)) Monate")
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                } header: {
                    Text("Lebensschätzung")
                } footer: {
                    Text("Eine grobe, statistische Schätzung zur Motivation – keine medizinische Aussage.")
                }

                if !store.earlierPurchases.isEmpty {
                    Section("Frühere Monate") {
                        ForEach(store.earlierPurchases) { purchase in
                            PurchaseRow(purchase: purchase)
                        }
                    }
                }
            }
            .navigationTitle(store.currentMonthName)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var defaultBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -27, to: .now) ?? .now
    }
}

private struct PurchaseRow: View {
    let purchase: Purchase

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.08), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(purchase.store)
                    .fontWeight(.semibold)
                Text("\(Formatters.longDate(purchase.date)) · \(purchase.itemCount) Artikel")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
            Spacer()
            Text(Formatters.euro(purchase.total))
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }
}
