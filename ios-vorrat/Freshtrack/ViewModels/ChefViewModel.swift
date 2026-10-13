import Foundation
import Observation

/// Chat state for the AI chef, persisted between launches.
@Observable
final class ChefViewModel {
    private(set) var messages: [ChatMessage] = []
    var draft: String = ""
    private(set) var isThinking: Bool = false
    private(set) var errorMessage: String?

    private let fileName = "chef_chat.json"

    let suggestions: [String] = [
        "Was kann ich heute kochen?",
        "Schnelles Frühstück mit meinem Freshtrack",
        "Was sollte ich zuerst verbrauchen?",
        "Vegetarisches Abendessen für zwei"
    ]

    init() {
        messages = Persistence.load([ChatMessage].self, from: fileName) ?? []
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking
    }

    func send(_ text: String? = nil, pantry: [String]) {
        let content = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isThinking else { return }
        draft = ""
        errorMessage = nil
        messages.append(ChatMessage(role: .user, text: content))
        save()
        Task { await respond(pantry: pantry) }
    }

    func retry(pantry: [String]) {
        guard !isThinking, messages.last?.role == .user else { return }
        errorMessage = nil
        Task { await respond(pantry: pantry) }
    }

    func clear() {
        messages = []
        errorMessage = nil
        save()
    }

    private func respond(pantry: [String]) async {
        isThinking = true
        defer { isThinking = false }
        let history: [ChatTurn] = messages.suffix(12).map { message in
            if message.role == .assistant, let recipe = message.recipe {
                return ChatTurn(role: "assistant", content: "\(message.text)\nRezept: \(recipe.title)")
            }
            return ChatTurn(role: message.role.rawValue, content: message.text)
        }
        do {
            let reply = try await AIService.chef(history: history, pantry: pantry)
            let message = ChatMessage(role: .assistant, text: reply.message, recipe: reply.recipe, closing: reply.closing)
            messages.append(message)
            save()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? AIError.server.errorDescription
        }
    }

    private func save() {
        Persistence.save(messages, to: fileName)
    }
}
