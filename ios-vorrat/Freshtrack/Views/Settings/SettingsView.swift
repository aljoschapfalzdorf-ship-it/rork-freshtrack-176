import SwiftUI
import AuthenticationServices

/// "Einstellungen" tab: Apple sign-in (Rork Auth), profile and app info.
struct SettingsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(PantryStore.self) private var store
    @Environment(ProManager.self) private var pro

    @State private var showsSignOutConfirmation = false
    @State private var showsDeleteConfirmation = false
    @State private var showsPaywall = false
    @State private var showsTerms = false
    @State private var isDeletingAccount = false

    var body: some View {
        @Bindable var auth = auth

        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    profileCard
                    proCard
                    developerRow
                    if auth.user != nil {
                        statsCard
                    }
                    aboutCard

                    if auth.user != nil {
                        Button("Abmelden") { showsSignOutConfirmation = true }
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.secondary)
                            .padding(.top, 6)

                        // Account endgültig löschen: entfernt die Sitzung und
                        // sämtliche lokal gespeicherten Daten.
                        Button(role: .destructive) { showsDeleteConfirmation = true } label: {
                            HStack(spacing: 8) {
                                if isDeletingAccount {
                                    ProgressView()
                                        .tint(.red)
                                } else {
                                    Image(systemName: "trash")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                Text("Account löschen")
                                    .font(.body.weight(.semibold))
                            }
                            .foregroundStyle(.red)
                        }
                        .disabled(isDeletingAccount)
                        .accessibilityLabel("Account löschen")
                    }

                    Text("Deine Freshtracksdaten werden ausschließlich lokal auf deinem iPhone gespeichert.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .background(AtmosphereBackground())
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .sensoryFeedback(.success, trigger: auth.user != nil)
        }
        .alert("Anmeldung fehlgeschlagen", isPresented: $auth.showError) {
            Button("OK") {}
        } message: {
            Text(auth.errorMessage)
        }
        .confirmationDialog("Wirklich abmelden?", isPresented: $showsSignOutConfirmation, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) {
                Task { await auth.signOut() }
            }
            Button("Abbrechen", role: .cancel) {}
        }
        .confirmationDialog("Account endgültig löschen?\n\nAlle Daten auf diesem Gerät (Freshtrack, KI-Koch-Chat, Budget) werden unwiderruflich gelöscht und du wirst abgemeldet.", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
            Button("Account löschen", role: .destructive) {
                deleteAccount()
            }
            Button("Abbrechen", role: .cancel) {}
        }
        .sheet(isPresented: $showsPaywall) {
            ProPaywallView()
        }
        .sheet(isPresented: $showsTerms) {
            TermsView()
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Profile

    @ViewBuilder
    private var profileCard: some View {
        if let user = auth.user {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    avatar
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.name?.isEmpty == false ? user.name! : user.email)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let name = user.name, !name.isEmpty {
                            Text(user.email)
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondary)
                                .lineLimit(1)
                        }
                        Label("Mit Apple angemeldet", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .glassSurface(Capsule())
                            .padding(.top, 4)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentCard()
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        } else {
            VStack(spacing: 14) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.white)
                    .frame(width: 88, height: 88)
                    .glassSurface(Circle())
                    .padding(.top, 26)
                Text("Willkommen bei Freshtrack")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text("Melde dich an, um dein Profil mit Bild und Namen zu sehen. Deine Freshtracksdaten bleiben dabei lokal gespeichert.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
                Group {
                    if auth.isSigningIn {
                        ProgressView()
                            .tint(.white)
                            .frame(height: 52)
                    } else {
                        SignInWithAppleButton(.signIn) { _ in
                            // Auth läuft über Rorks Web-OAuth; der Button ist nur der Einstieg.
                        } onCompletion: { _ in
                            Task { await auth.signIn(provider: "apple") }
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 52)
                        .clipShape(.capsule)
                    }
                }
                .disabled(auth.isSigningIn)
                .padding(.horizontal, 4)
                .padding(.bottom, 26)
            }
            .frame(maxWidth: .infinity)
            .contentCard()
        }
    }

    private var avatar: some View {
        Group {
            if let urlString = auth.user?.picture, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else if phase.error != nil {
                        monogram
                    } else {
                        ZStack {
                            Theme.surfaceHigh
                            ProgressView().tint(.white)
                        }
                    }
                }
            } else {
                monogram
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(.circle)
        .overlay { Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5) }
        .grayscale(1)
    }

    /// Monochrome fallback: initials on a raised surface.
    private var monogram: some View {
        ZStack {
            Theme.surfaceHigh
            if initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                Text(initials)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
    }

    private var initials: String {
        guard let user = auth.user else { return "" }
        let source = user.name?.isEmpty == false ? user.name! : user.email
        let words = source.split(separator: " ")
        let first = words.first?.first.map(String.init) ?? ""
        let last = words.count > 1 ? String(words.last!.first!) : ""
        return (first + last).uppercased()
    }

    // MARK: Pro

    private var proCard: some View {
        Button {
            SoundPlayer.playChime()
            showsPaywall = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 48, height: 48)
                    .background(.white, in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Vorrat Pro")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(pro.isPro ? "Aktiv – alle Features freigeschaltet" : "Mehr Statistiken & KI-Koch · 0,99 € / Monat")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if pro.isPro {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                } else {
                    Text("Pro")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.white, in: .capsule)
                }
            }
            .padding(16)
            .contentCard()
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(pro.isPro ? "Vorrat Pro ist aktiv" : "Vorrat Pro abonnieren, 0,99 Euro im Monat")
    }

    /// Developer-Schalter: aktiviert Pro komplett kostenlos (ohne Kauf),
    /// zweiter Tipp nimmt die Freischaltung zurück.
    private var developerRow: some View {
        Button {
            withAnimation(.snappy) { pro.toggleDeveloperMode() }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Theme.surfaceHigh, in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Developer")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(pro.developerMode ? "Aktiv – Pro kostenlos freigeschaltet" : "Pro-Modus kostenlos zum Testen")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(pro.developerMode ? "Ein" : "Aus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(pro.developerMode ? Color.white : Theme.surfaceHigh, in: .capsule)
            }
            .padding(16)
            .contentCard()
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(pro.developerMode ? "Developer-Modus ist aktiv" : "Developer-Modus einschalten")
    }

    // MARK: Stats

    private var statsCard: some View {
        VStack(spacing: 0) {
            statRow(icon: "basket", label: "Produkte im Freshtrack", value: "\(store.products.count)")
            Divider().overlay(Theme.hairline)
            statRow(icon: "wallet.bifold", label: "Ausgaben diesen Monat", value: Formatters.euro(store.monthSpent))
            Divider().overlay(Theme.hairline)
            statRow(icon: "target", label: "Monatsbudget", value: Formatters.euro(store.monthlyBudget))
        }
        .padding(.vertical, 6)
        .contentCard(radius: 22)
    }

    private func statRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.surfaceHigh, in: .rect(cornerRadius: 10))
            Text(label)
                .font(.body)
                .foregroundStyle(Theme.secondary)
            Spacer()
            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: About

    private var aboutCard: some View {
        VStack(spacing: 0) {
            statRow(icon: "info.circle", label: "Version", value: appVersion)
            Divider().overlay(Theme.hairline)
            Button {
                showsTerms = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Theme.surfaceHigh, in: .rect(cornerRadius: 10))
                    Text("AGB")
                        .font(.body)
                        .foregroundStyle(Theme.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.secondary.opacity(0.6))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Allgemeine Geschäftsbedingungen öffnen")
        }
        .padding(.vertical, 6)
        .contentCard(radius: 22)
    }

    /// Löscht alle lokalen Daten und meldet ab (Account-Ende).
    private func deleteAccount() {
        isDeletingAccount = true
        Task {
            store.deleteAllLocalData()
            pro.resetDeveloperMode()
            await auth.signOut()
            isDeletingAccount = false
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .environment(AuthManager())
        .environment(PantryStore())
        .environment(ProManager())
        .preferredColorScheme(.dark)
}
