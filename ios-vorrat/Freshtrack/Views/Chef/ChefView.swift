import SwiftUI

/// "KI-Koch" tab: chat with an AI that knows your pantry.
struct ChefView: View {
    @Environment(PantryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(ProManager.self) private var pro
    @State private var model: ChefViewModel = ChefViewModel()
    @State private var showsPaywall: Bool = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if model.messages.isEmpty {
                            welcome
                        }
                        if !pro.isPro && model.messages.isEmpty {
                            proHint
                        }
                        ForEach(model.messages) { message in
                            MessageView(message: message)
                            .id(message.id)
                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                        }
                        if model.isThinking {
                            ThinkingBubble().id("thinking")
                        }
                        if let error = model.errorMessage {
                            errorBubble(error).id("error")
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .animation(.spring(response: 0.45, dampingFraction: 0.85), value: model.messages)
                    .animation(.easeInOut, value: model.isThinking)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .background(AtmosphereBackground())
                .onChange(of: model.messages.count) { _, _ in scrollToBottom(proxy) }
                .onChange(of: model.isThinking) { _, _ in scrollToBottom(proxy) }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationTitle("KI-Koch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !model.messages.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation { model.clear() }
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel("Neuer Chat")
                    }
                }
            }
        }
        .onAppear(perform: consumePendingPrompt)
        .onChange(of: router.pendingChefPrompt) { _, _ in consumePendingPrompt() }
        .sensoryFeedback(.impact(weight: .light), trigger: model.messages.count)
        .sheet(isPresented: $showsPaywall) {
            ProPaywallView()
        }
    }

    /// Alle Sends laufen durch das Pro-Gate – ohne Abo öffnet sich der Paywall.
    private func send(_ text: String? = nil) {
        guard pro.isPro else {
            showsPaywall = true
            return
        }
        model.send(text, pantry: store.pantryDescription)
    }

    private func consumePendingPrompt() {
        guard let prompt = router.pendingChefPrompt else { return }
        router.pendingChefPrompt = nil
        send(prompt)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    // MARK: Pieces

    private var proHint: some View {
        Button {
            showsPaywall = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 36, height: 36)
                    .background(.white, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("KI-Koch ist Teil von Pro")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("0,99 € im Monat · jederzeit kündbar")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
            }
            .padding(14)
            .contentCard(radius: 20)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("KI-Koch ist Teil von Vorrat Pro. Für 0,99 Euro im Monat abonnieren.")
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "frying.pan")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .glassSurface(Circle())
                .padding(.top, 24)
            VStack(alignment: .leading, spacing: 6) {
                Text("Was kochen wir heute?")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                Text(store.products.isEmpty
                     ? "Scanne zuerst einen Kassenbon – dann weiß ich, was du zu Hause hast."
                     : "Ich kenne deine \(store.products.count) Produkte zu Hause und schlage dir passende Rezepte mit Schritt-für-Schritt-Anleitung vor.")
                    .font(.body)
                    .foregroundStyle(Theme.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.suggestions, id: \.self) { suggestion in
                    Button {
                        send(suggestion)
                    } label: {
                        HStack {
                            Text(suggestion)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.secondary)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                        .glassSurface(Capsule(), interactive: true)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .padding(.bottom, 12)
    }

    private func errorBubble(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(text, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.white)
            Button("Erneut versuchen") { model.retry(pantry: store.pantryDescription) }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.white, in: .capsule)
        }
        .padding(14)
        .contentCard(radius: 20)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(model.suggestions, id: \.self) { suggestion in
                    Button(suggestion) { send(suggestion) }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .glassSurface(Circle(), interactive: true)
            }
            .accessibilityLabel("Vorschläge")

            TextField("Frag deine KI …", text: $model.draft, axis: .vertical)
                .lineLimit(1...4)
                .font(.body)
                .foregroundStyle(.white)
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit { send() }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .glassSurface(RoundedRectangle(cornerRadius: 25))

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(model.canSend ? .black : .white.opacity(0.5))
                    .frame(width: 50, height: 50)
                    .background(model.canSend ? Color.white : Color.white.opacity(0.08), in: .circle)
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5) }
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .disabled(!model.canSend)
            .animation(.snappy, value: model.canSend)
            .accessibilityLabel("Senden")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct MessageView: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 60)
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Theme.surfaceHigh, in: .rect(cornerRadius: 22))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 10) {
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.body)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentCard(radius: 22)
                        .padding(.trailing, message.recipe == nil ? 40 : 60)
                }
                if let recipe = message.recipe {
                    RecipeCard(recipe: recipe)
                }
                if let closing = message.closing, !closing.isEmpty {
                    Text(closing)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 4)
                }
            }
        }
    }
}

private struct ThinkingBubble: View {
    @State private var phase: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.white)
                    .frame(width: 7, height: 7)
                    .opacity(phase ? 1 : 0.25)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.18), value: phase)
            }
            Text("Koch überlegt …")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .padding(.leading, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentCard(radius: 22)
        .onAppear { phase = true }
    }
}
