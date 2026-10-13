import SwiftUI

/// Lets the user confirm which recognised items go into the pantry.
struct ReceiptReviewView: View {
    @Environment(PantryStore.self) private var store
    @State private var receipt: ScannedReceipt
    let onRescan: () -> Void
    let onConfirm: (ScannedReceipt) -> Void

    init(receipt: ScannedReceipt, onRescan: @escaping () -> Void, onConfirm: @escaping (ScannedReceipt) -> Void) {
        _receipt = State(initialValue: receipt)
        self.onRescan = onRescan
        self.onConfirm = onConfirm
    }

    private var selectedCount: Int { receipt.items.filter(\.isSelected).count }
    private var selectedTotal: Double { receipt.items.filter(\.isSelected).reduce(0) { $0 + $1.price } }

    var body: some View {
        ZStack {
            AtmosphereBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    VStack(spacing: 10) {
                        ForEach($receipt.items) { $item in
                            ScannedItemRow(item: $item)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .top) {
            HStack {
                GlassCircleButton(systemImage: "arrow.counterclockwise", size: 44, iconSize: 16, label: "Neu scannen", action: onRescan)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                onConfirm(receipt)
            } label: {
                HStack {
                    Text(selectedCount == 1 ? "1 Produkt hinzufügen" : "\(selectedCount) Produkte hinzufügen")
                    Spacer()
                    Text(Formatters.euro(selectedTotal))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .font(.headline)
                .foregroundStyle(.black)
                .padding(.horizontal, 22)
                .frame(height: 58)
                .background(.white, in: .capsule)
            }
            .buttonStyle(PressableStyle())
            .disabled(selectedCount == 0)
            .opacity(selectedCount == 0 ? 0.4 : 1)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .animation(.snappy, value: selectedTotal)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Erkannt")
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(Theme.secondary)
            HStack(spacing: 10) {
                if let hex = receipt.storeColorHex, let color = Color(hex: hex) {
                    Circle()
                        .fill(color)
                        .frame(width: 16, height: 16)
                        .shadow(color: color.opacity(0.6), radius: 6)
                }
                Text(receipt.store)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if !store.hasStore(receipt.store) {
                    Text("Neu")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white, in: .capsule)
                }
            }
            HStack(spacing: 6) {
                Text("\(receipt.items.count) Artikel")
                if let date = receipt.date {
                    Text("·")
                    Text(Formatters.longDate(date))
                }
                if let total = receipt.total {
                    Text("·")
                    Text("Summe \(Formatters.euro(total))")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Theme.secondary)
            Text("Tippe Artikel an, die nicht in deinen Freshtrack sollen.")
                .font(.footnote)
                .foregroundStyle(Theme.secondary.opacity(0.8))
                .padding(.top, 4)
        }
        .padding(.top, 4)
    }
}

private struct ScannedItemRow: View {
    @Binding var item: ScannedItem

    var body: some View {
        Button {
            withAnimation(.snappy) { item.isSelected.toggle() }
        } label: {
            HStack(spacing: 14) {
                ProductImage(category: item.category)
                    .frame(width: 64, height: 64)
                    .clipShape(.rect(cornerRadius: 14))
                    .saturation(item.isSelected ? 1 : 0)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(item.quantity)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 8)
                Text(Formatters.euro(item.price))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(item.isSelected ? .white : Theme.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(10)
            .contentCard(radius: 22)
            .opacity(item.isSelected ? 1 : 0.5)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .sensoryFeedback(.selection, trigger: item.isSelected)
    }
}
