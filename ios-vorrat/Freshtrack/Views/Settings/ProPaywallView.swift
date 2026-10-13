import SwiftUI

/// Paywall für Vorrat Pro: 0,99 € im Monat, Kauf über die Apple-ID (StoreKit).
struct ProPaywallView: View {
    @Environment(ProManager.self) private var pro
    @Environment(\.dismiss) private var dismiss

    @State private var succeeded: Bool = false

    var body: some View {
        ZStack {
            AtmosphereBackground()
            ScrollView {
                VStack(spacing: 20) {
                    if pro.isPro || succeeded {
                        activeContent
                    } else {
                        offerContent
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 64)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        // Feste Vollhöhe: Fenster lässt sich weder verkleinern noch wegwischen.
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .glassSurface(Circle(), interactive: true)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Schließen")
            .padding(.trailing, 16)
            .padding(.top, 10)
        }
        .sensoryFeedback(.success, trigger: succeeded)
        .sensoryFeedback(.success, trigger: pro.isPro)
    }

    // MARK: Offer

    private var offerContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "crown.fill")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 86, height: 86)
                .glassSurface(Circle())
                .overlay { Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6) }
                .shadow(color: .white.opacity(0.18), radius: 26)
                .padding(.top, 6)

            VStack(spacing: 8) {
                Text("Vorrat Pro")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                Text("Alle Features freischalten – für 0,99 € im Monat.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                featureRow(icon: "chart.bar.fill", title: "Erweiterte Statistiken", subtitle: "Kategorien, Wochen und Top-Ausgaben")
                featureRow(icon: "frying.pan.fill", title: "KI-Koch", subtitle: "Rezepte aus deinem Freshtrack – unbegrenzt")
                featureRow(icon: "doc.text.viewfinder", title: "Lokaler Kassenbon-Scan", subtitle: "Läuft auf dem Gerät mit Apple Vision")
            }

            purchaseButton

            if let error = pro.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            Button("Käufe wiederherstellen") {
                Task { await pro.restore() }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.secondary)

            Text("Abo läuft monatlich automatisch weiter. Jederzeit in den iOS-Einstellungen kündbar.")
                .font(.caption2)
                .foregroundStyle(Theme.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
        }
        .animation(.easeOut(duration: 0.25), value: pro.errorMessage)
    }

    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.10), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentCard(radius: 18)
    }

    private var purchaseButton: some View {
        Button {
            Task {
                let ok = await pro.purchase()
                if ok {
                    succeeded = true
                    try? await Task.sleep(for: .seconds(1.2))
                    dismiss()
                }
            }
        } label: {
            HStack(spacing: 10) {
                if pro.isPurchasing {
                    ProgressView().tint(.black)
                } else {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text("\(pro.priceText) / Monat")
                        .font(.body.weight(.bold))
                }
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(.white, in: .capsule)
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .disabled(pro.isPurchasing)
        .accessibilityLabel("Pro für \(pro.priceText) im Monat abonnieren")
    }

    // MARK: Active

    private var activeContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 86, height: 86)
                .glassSurface(Circle())
                .padding(.top, 10)
            Text(pro.isPro ? "Pro ist aktiv" : "Danke für dein Abo!")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text("Erweiterte Statistiken und der KI-Koch sind jetzt freigeschaltet.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)

            Button("Fertig") { dismiss() }
                .font(.body.weight(.semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(.white, in: .capsule)
                .padding(.top, 8)
        }
    }
}

#Preview {
    ProPaywallView()
        .environment(ProManager())
}
