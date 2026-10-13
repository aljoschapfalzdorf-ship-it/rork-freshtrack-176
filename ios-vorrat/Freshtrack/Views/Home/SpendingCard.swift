import SwiftUI

/// Glass card with this month's spending, budget progress and reset countdown.
struct SpendingCard: View {
    let spent: Double
    let progress: Double
    let daysUntilReset: Int

    @State private var animatedProgress: Double = 0

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "wallet.bifold")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Color.white.opacity(0.10), in: .circle)
                .overlay { Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5) }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Formatters.euro(spent))
                        .font(.system(size: 34, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(value: spent))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("diesen Monat")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(LinearGradient(colors: [.white.opacity(0.85), .white], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(geo.size.width * animatedProgress, animatedProgress > 0 ? 8 : 0))
                            .shadow(color: .white.opacity(0.35), radius: 6)
                    }
                }
                .frame(height: 8)

                Label(resetText, systemImage: "calendar")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .glassSurface(RoundedRectangle(cornerRadius: 30), interactive: true)
        .onAppear {
            withAnimation(.spring(response: 1.1, dampingFraction: 0.8).delay(0.15)) { animatedProgress = progress }
        }
        .onChange(of: progress) { _, new in
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) { animatedProgress = new }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Formatters.euro(spent)) diesen Monat ausgegeben. \(resetText)")
    }

    private var resetText: String {
        daysUntilReset == 1 ? "Zurücksetzung morgen" : "Zurücksetzung in \(daysUntilReset) Tagen"
    }
}
