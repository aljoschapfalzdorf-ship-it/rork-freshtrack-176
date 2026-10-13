import SwiftUI

/// Root: three-tab switcher (Zuhause / KI-Koch / Einstellungen), Liquid Glass on iOS 26.
struct ContentView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Zuhause", systemImage: "house.fill", value: AppTab.home) {
                HomeView()
            }
            Tab("KI-Koch", systemImage: "frying.pan.fill", value: AppTab.chef) {
                ChefView()
            }
            Tab("Einstellungen", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tint(.white)
        .sensoryFeedback(.selection, trigger: router.tab)
    }
}

#Preview {
    ContentView()
        .environment(PantryStore())
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}
