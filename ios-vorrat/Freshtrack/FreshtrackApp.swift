import SwiftUI

@main
struct FreshtrackApp: App {
    @State private var store: PantryStore = PantryStore()
    @State private var router: AppRouter = AppRouter()
    @State private var auth: AuthManager = AuthManager()
    @State private var pro: ProManager = ProManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(router)
                .environment(auth)
                .environment(pro)
                .preferredColorScheme(.dark)
                .task { BudgetNotificationService.shared.requestAuthorization() }
                .onChange(of: scenePhase) { phase in
                    // Widgets bei jedem Start/Vordergrund/Hintergrund-Wechsel
                    // sofort mit aktuellen Daten versorgen.
                    if phase == .active || phase == .background {
                        store.syncWidget()
                    }
                }
        }
    }
}
