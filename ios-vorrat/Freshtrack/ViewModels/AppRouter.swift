import Foundation
import Observation

nonisolated enum AppTab: Hashable, Sendable {
    case home, chef, settings
}

/// Cross-screen navigation: tab selection and prompts handed to the AI chef.
@Observable
final class AppRouter {
    var tab: AppTab = .home
    var pendingChefPrompt: String?

    func askChef(_ prompt: String) {
        pendingChefPrompt = prompt
        tab = .chef
    }
}
