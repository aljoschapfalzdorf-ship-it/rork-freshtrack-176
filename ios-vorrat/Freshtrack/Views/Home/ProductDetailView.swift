import SwiftUI

/// Pushed detail for a pantry product.
struct ProductDetailView: View {
    let productID: UUID

    @Environment(PantryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    private var product: Product? { store.products.first { $0.id == productID } }

    var body: some View {
        Group {
            if let product {
                content(product)
            } else {
                ContentUnavailableView("Produkt entfernt", systemImage: "basket", description: Text("Dieses Produkt ist nicht mehr in deinem Freshtrack."))
            }
        }
        .background(AtmosphereBackground())
        .toolbar(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ product: Product) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ProductImage(category: product.category)
                    .frame(height: 320)
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [.clear, .black], startPoint: .center, endPoint: .bottom)
                            .allowsHitTesting(false)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text(product.name)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                    Text(product.quantity)
                        .font(.title3)
                        .foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, -60)

                VStack(spacing: 0) {
                    infoRow("Preis", Formatters.euro(product.price), icon: "eurosign")
                    Divider().overlay(Theme.hairline).padding(.leading, 52)
                    infoRow("Gekauft", Formatters.longDate(product.purchasedAt), icon: "calendar")
                    if let storeName = product.store {
                        Divider().overlay(Theme.hairline).padding(.leading, 52)
                        infoRow("Geschäft", storeName, icon: "storefront")
                    }
                }
                .contentCard(radius: 22)
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 24)
        }
        .ignoresSafeArea(edges: .top)
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button {
                    router.askChef("Was kann ich mit \(product.name) kochen?")
                } label: {
                    Label("Rezeptidee vom KI-Koch", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(.white, in: .capsule)
                }
                .buttonStyle(PressableStyle())

                Button(role: .destructive) {
                    store.delete(product)
                    dismiss()
                } label: {
                    Label("Aus Freshtrack löschen", systemImage: "trash")
                        .font(.headline)
                        .foregroundStyle(Theme.destructive)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .glassSurface(Capsule(), interactive: true)
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func infoRow(_ title: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 24)
            Text(title)
                .foregroundStyle(Theme.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .font(.body)
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
    }
}
