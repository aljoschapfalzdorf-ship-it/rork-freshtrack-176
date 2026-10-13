import SwiftUI

/// AGB-Fenster: gleicher Aufbau wie das Pro-Fenster (Vollhöhe, Glas-
/// Hintergrund, Schließen-Kreis oben rechts), nur mit Rechtstext.
struct TermsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AtmosphereBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    ForEach(TermsSection.all) { section in
                        sectionView(section)
                    }
                    footer
                }
                .padding(.horizontal, 22)
                .padding(.top, 64)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        // Gleicher Rahmen wie das Abo-Fenster: feste Vollhöhe, kein Griffel.
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .glassSurface(Circle(), interactive: true)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Schließen")
            .padding(.trailing, 16)
            .padding(.top, 10)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 86, height: 86)
                .glassSurface(Circle())
                .overlay { Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6) }
                .padding(.top, 6)
            Text("Allgemeine Geschäftsbedingungen")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("für die Nutzung von Freshtrack („Vorrat“)")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionView(_ section: TermsSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .lineSpacing(3)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(radius: 18)
    }

    private var footer: some View {
        Text("Stand: Oktober 2026")
            .font(.caption2)
            .foregroundStyle(Theme.secondary.opacity(0.7))
            .frame(maxWidth: .infinity)
    }
}

/// Ein Abschnitt der AGB (Titel + Absätze).
private nonisolated struct TermsSection: Identifiable {
    let title: String
    let paragraphs: [String]
    var id: String { title }

    static let all: [TermsSection] = [
        .init(title: "1 · Geltungsbereich und Anbieter", paragraphs: [
            "Diese Bedingungen regeln die Nutzung der App Freshtrack („Vorrat“). Anbieter ist der Entwickler, unter dem die App im App Store veröffentlicht ist. Mit der Installation und Nutzung der App akzeptierst du diese Bedingungen.",
            "Die App richtet sich ausschließlich an Verbraucher im Sinne des § 13 BGB. Es gilt deutsches Recht.",
        ]),
        .init(title: "2 · Leistungen der App", paragraphs: [
            "Freshtrack verwaltet deinen Haushaltsvorrat: Kassenbons werden erfasst, Ausgaben und Budget ausgewertet und dein Bestand auf dem Gerät gespeichert. Die Kernfunktionen sind kostenlos.",
            "Optional erweiterst du die App um „Vorrat Pro“ (Abo, siehe Abschnitt 5).",
        ]),
        .init(title: "3 · KI-Koch und Weitergabe von Daten an Google", paragraphs: [
            "Der KI-Koch (Teil von Vorrat Pro) nutzt das Sprachmodell Google Gemini der Google LLC („Google“). Anfragen und der zugehörige Chatverlauf sowie die Liste deiner aktuell vorhandenen Produkte werden zur Antworterstellung an die Serversysteme von Google übertragen und dort verarbeitet.",
            "Google verarbeitet diese Daten nach eigenen Maßgaben; Einzelheiten findest du in der Datenschutzerklärung von Google (policies.google.com/privacy) und den Nutzungsbedingungen für generative KI. Für die Übertragung und Verarbeitung durch Google gelten deren Bestimmungen.",
            "Die weitere Verarbeitung (Anzeige im Chat, lokale Speicherung des Chatverlaufs) erfolgt ausschließlich auf deinem Gerät.",
        ]),
        .init(title: "4 · Lokale Verarbeitung – Kassenbon-Scan", paragraphs: [
            "Das Einscannen von Kassenbons läuft vollständig lokal auf deinem iPhone: Die Texterkennung nutzt das On-Device-Framework Apple Vision. Fotos und erkannte Boninhalte verlassen dein Gerät dafür nicht und werden nicht an uns, Google oder Dritte weitergegeben.",
            "Deine gesamten Freshtrack-Daten (Produkte, Käufe, Budget, Chatverlauf) werden ausschließlich lokal auf deinem iPhone gespeichert. Es findet kein Cloud-Sync statt.",
        ]),
        .init(title: "5 · In-App-Käufe und Abonnement (Vorrat Pro)", paragraphs: [
            "Vorrat Pro ist ein kostenpflichtiges Abonnement über 0,99 € pro Monat und wird als Auto-Renewable-Subscription über den App Store der Apple Distribution International Ltd. abgerechnet. Preis und Laufzeit werden dir vor dem Abschluss angezeigt; der Preis ist ein Endpreis inklusive der gesetzlichen Umsatzsteuer.",
            "Vertragsschluss: Der Kaufvertrag über das Abo kommt zwischen dir und Apple zustande, wenn du den Kauf mit deiner Apple-ID bestätigst. Die Abrechnung erfolgt über deine bei Apple hinterlegte Zahlungsmethode.",
            "Laufzeit und Kündigung: Das Abo verlängert sich automatisch um den jeweiligen Abrechnungszeitraum, sofern du es nicht kündigst. Die Verlängerung wird dir von Apple mindestens 24 Stunden vor Ablauf des aktuellen Zeitraums angezeigt. Du kannst das Abo jederzeit in den Einstellungen deines Apple-Kontos (App Store → Abonnements) kündigen; die Kündigung wirkt zum Ende des laufenden Abrechnungszeitraums. Nach Ablauf des bereits bezahlten Zeitraums endet der Zugang zu Vorrat Pro.",
            "Widerrufsrecht: Als Verbraucher hast du bei Verträgen im Fernabsatz ein Widerrufsrecht von 14 Tagen ab Vertragsschluss, ohne Angabe von Gründen. Erklärung gegenüber Apple (über dein Apple-Konto bzw. reportaproblem.apple.com) oder gegenüber dem Anbieter. Bei digitalen Inhalten erlischt das Widerrufsrecht vorzeitig, wenn du der sofortigen Lieferung ausdrücklich zustimmst und deine Kenntnis vom Erlöschen dokumentierst; andernfalls entsteht die Zahlungspflicht erst mit Ablauf der 14 Tage.",
            "Gewährleistung: Bei Mängeln der bezogenen Leistung bestehen die gesetzlichen Gewährleistungsrechte. Für die Abwicklung von Mängeln im Zusammenhang mit dem Kauf über den App Store wende dich zusätzlich an Apple.",
            "Gemäß § 36 VSBG sind wir nicht verpflichtet und nicht bereit, an einem Streitbeilegungsverfahren vor einer Verbraucherschlichtungsstelle teilzunehmen.",
        ]),
        .init(title: "6 · Anmeldung mit Apple", paragraphs: [
            "Die Anmeldung erfolgt über „Mit Apple anmelden“ (Sign in with Apple). Dabei verarbeitet der Anmeldedienst deine Apple-Kennung, Name und E-Mail-Adresse (nur, sofern du sie freigibst). Die Zugangsdaten werden sicher auf dem Gerät (Schlüsselspeicher) gespeichert. Du kannst die Anmeldung jederzeit über „Abmelden“ beenden.",
        ]),
        .init(title: "7 · Haftung", paragraphs: [
            "Wir haften unbeschränkt bei Vorsatz und grober Fahrlässigkeit sowie bei Verletzung von Leben, Körper oder Gesundheit. Bei leichter Fahrlässigkeit haften wir nur bei Verletzung wesentlicher Vertragspflichten, begrenzt auf den vorhersehbaren, vertragstypischen Schaden.",
            "KI-Antworten (KI-Koch) sind automatische Vorschläge ohne Gewähr. Rezeptangaben, Mengen und Lagerzeiten von Lebensmitteln bitte vor der Zubereitung selbst prüfen; die Nutzung erfolgt auf eigene Verantwortung.",
        ]),
        .init(title: "8 · Änderungen und Schlussbestimmungen", paragraphs: [
            "Wir können diese Bedingungen anpassen, soweit die Änderungen bei angemessener Berücksichtigung deiner Interessen nicht zu Lasten deiner Wohnung gehen. Über Änderungen informieren wir in der App; sie werden wirksam, wenn du die App nach Ankündigung weiter nutzt.",
            "Sollten einzelne Bestimmungen unwirksam sein, bleibt die Wirksamkeit der übrigen Bedingungen unberührt. Es gilt deutsches Recht.",
        ]),
    ]
}

#Preview {
    TermsView()
}
