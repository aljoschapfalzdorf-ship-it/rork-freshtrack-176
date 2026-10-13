import SwiftUI

/// Large feed card: photo on the left, name, amount and price on the right.
struct ProductCard: View {
    let product: Product
    var isFresh: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            ProductImage(category: product.category)
                .frame(width: 150)

            VStack(alignment: .leading, spacing: 4) {
                if isFresh {
                    Text("NEU")
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.white, in: .capsule)
                        .transition(.scale.combined(with: .opacity))
                }
                Text(product.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(product.quantity)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(Formatters.euro(product.price))
                    .font(.system(size: 26, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 18)
            .padding(.leading, 18)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .padding(.trailing, 18)
        }
        .frame(height: 150)
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
        .contentCard()
        .overlay {
            if isFresh {
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(Color.white.opacity(0.7), lineWidth: 1.2)
                    .shadow(color: .white.opacity(0.4), radius: 8)
            }
        }
        .contentShape(.rect(cornerRadius: Theme.cardRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(product.name), \(product.quantity), \(Formatters.euro(product.price))")
    }
}
