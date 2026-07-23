import SwiftUI

struct OnboardingView: View {
    let onSkip: () -> Void
    let onStartSetup: () -> Void

    @State private var selectedPage = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if selectedPage < OnboardingPage.allCases.count - 1 {
                        Button("Überspringen", action: onSkip)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                TabView(selection: $selectedPage) {
                    ForEach(Array(OnboardingPage.allCases.enumerated()), id: \.element.id) { index, page in
                        ScrollView {
                            VStack(spacing: 24) {
                                Image(systemName: page.symbol)
                                    .font(.system(size: 64, weight: .semibold))
                                    .foregroundStyle(.tint)
                                    .frame(height: 90)

                                Text(LocalizedStringKey(page.title))
                                    .font(.largeTitle.bold())
                                    .multilineTextAlignment(.center)

                                Text(LocalizedStringKey(page.introduction))
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)

                                VStack(alignment: .leading, spacing: 16) {
                                    ForEach(page.bullets, id: \.self) { bullet in
                                        HStack(alignment: .top, spacing: 12) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.tint)
                                            Text(LocalizedStringKey(bullet))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                                .padding()
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 16)
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                HStack(spacing: 16) {
                    if selectedPage > 0 {
                        Button("Zurück") {
                            withAnimation { selectedPage -= 1 }
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        if selectedPage == OnboardingPage.allCases.count - 1 {
                            onStartSetup()
                        } else {
                            withAnimation { selectedPage += 1 }
                        }
                    } label: {
                        Text(LocalizedStringKey(
                            selectedPage == OnboardingPage.allCases.count - 1 ? "Jetzt einrichten" : "Weiter"
                        ))
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding()
            }
            .navigationTitle("Erste Schritte")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }
}

private enum OnboardingPage: String, CaseIterable, Identifiable {
    case welcome, profile, management, property, report, noiseProtocol, privacy

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .welcome: "building.2.crop.circle"
        case .profile: "person.text.rectangle"
        case .management: "building.2"
        case .property: "house.and.flag"
        case .report: "camera.viewfinder"
        case .noiseProtocol: "waveform.badge.plus"
        case .privacy: "lock.icloud"
        }
    }

    var title: String {
        switch self {
        case .welcome: "Willkommen bei der HV Melde App"
        case .profile: "Absenderdaten einrichten"
        case .management: "Hausverwaltung hinterlegen"
        case .property: "Objekte anlegen"
        case .report: "Einen Vorfall melden"
        case .noiseProtocol: "Ruhestörungen länger dokumentieren"
        case .privacy: "Lokal und unter deiner Kontrolle"
        }
    }

    var introduction: String {
        switch self {
        case .welcome: "Dokumentiere Vorfälle strukturiert und sende einen übersichtlichen PDF-Brief an die zuständige Hausverwaltung."
        case .profile: "Diese Angaben erscheinen als Absender im Brief und müssen nur einmal erfasst werden."
        case .management: "Eine Hausverwaltung kann mit mehreren Objekten verknüpft werden."
        case .property: "Lege jede Wohnung, Garage oder andere Einheit an, für die du Meldungen erstellen möchtest."
        case .report: "Fotos stehen am Anfang, damit lokale Erkennung und EXIF-Daten die Erfassung unterstützen."
        case .noiseProtocol: "Ein Lärmprotokoll sammelt Vorfälle, Videos mit Ton und Einsätze über Wochen oder Monate in einer Zeitleiste."
        case .privacy: "Die App benötigt keinen zentralen Server und versendet nichts ohne deine Bestätigung."
        }
    }

    var bullets: [String] {
        switch self {
        case .welcome:
            ["Geschäftsbrief und Beweisfotos in einem PDF", "Fälle lokal speichern und als erledigt markieren", "Meldungen selbst per E-Mail versenden"]
        case .profile:
            ["Vorname, Nachname und vollständige Anschrift", "Telefonnummer und E-Mail-Adresse", "Die Daten bleiben zunächst auf deinem Gerät"]
        case .management:
            ["Name, Anschrift und Kontaktdaten", "Briefsprache: Deutsch, Italienisch, Englisch oder bilingual", "Die Melde-E-Mail wird beim zugehörigen Objekt festgelegt"]
        case .property:
            ["Interner Name und offizielle Objektbezeichnung", "Straße, Nummer, Top und Objekttyp", "Mieter oder Eigentümer sowie zuständige Hausverwaltung"]
        case .report:
            ["Bis zu zehn Fotos auswählen oder aufnehmen", "Aufnahmedatum des ersten Fotos wird als Vorfallzeitpunkt verwendet", "Erkannte Angaben prüfen, PDF erstellen und versenden"]
        case .noiseProtocol:
            ["Beginn und Ende jeder Ruhestörung getrennt von der Videodauer erfassen", "Video mit Ton nur bewusst starten und unverändert mit SHA-256 sichern", "Polizei- oder andere Einsätze mit Dienststelle, Namen und Aktennummer dokumentieren", "PDF oder vollständiges Beweispaket über Mail Drop beziehungsweise iCloud Drive teilen"]
        case .privacy:
            ["Fotoanalyse und Übersetzung erfolgen auf dem Gerät", "iCloud-Synchronisierung ist optional und verwendet deinen privaten Bereich", "Erkennung und KI-Übersetzung bleiben prüfbare Vorschläge"]
        }
    }
}
