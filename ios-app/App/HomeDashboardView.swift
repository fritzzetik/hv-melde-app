import HVMeldeCore
import SwiftUI

struct HomeDashboardView: View {
    @EnvironmentObject private var store: AppDataStore
    let openReport: () -> Void
    let openCases: () -> Void
    let openSettings: () -> Void

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Hausverwaltung MeldeApp", systemImage: "building.2.crop.circle")
                        .font(.title2.bold())
                    Text("Vorfall lokal dokumentieren, als PDF sichern und selbst versenden.")
                        .foregroundStyle(.secondary)
                    Button(action: openReport) {
                        Label(
                            store.incidentDraft == nil ? "Neue Meldung erstellen" : "Entwurf fortsetzen",
                            systemImage: store.incidentDraft == nil ? "plus.circle.fill" : "pencil.circle.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    NavigationLink {
                        NoiseProtocolsView()
                    } label: {
                        Label("Lärmprotokoll führen", systemImage: "waveform.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.vertical, 8)
            }

            Section("Übersicht") {
                Button(action: openCases) {
                    LabeledContent("Offene Fälle", value: "\(openCasesCount)")
                }
                NavigationLink {
                    NoiseProtocolsView()
                } label: {
                    LabeledContent("Laufende Lärmprotokolle", value: "\(openNoiseProtocolCount)")
                }
                if let latestCase {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Letzte Meldung")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(latestCase.category.rawValue)
                            .font(.headline)
                        Text("\(latestCase.propertyName) · \(latestCase.incidentAt.formatted(date: .numeric, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Einrichtung") {
                setupRow("Persönliche Daten", complete: profileIsComplete)
                setupRow("Objekt", complete: !store.state.properties.isEmpty)
                setupRow("Hausverwaltung und Melde-E-Mail", complete: recipientIsComplete)
                if !setupIsComplete {
                    Button("Einrichtung abschließen", action: openSettings)
                }
            }

            Section {
                Label(
                    store.iCloudSyncEnabled
                        ? "Daten und Dokumente werden zusätzlich im privaten iCloud-Bereich gesichert."
                        : "Fotos, Fälle und Einstellungen bleiben lokal auf diesem Gerät.",
                    systemImage: "lock.shield"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Start")
    }

    private var openCasesCount: Int {
        store.state.reportedCases.filter { $0.status == .open }.count
    }

    private var latestCase: StoredReportedCase? {
        store.state.reportedCases.max { $0.createdAt < $1.createdAt }
    }

    private var openNoiseProtocolCount: Int {
        store.state.noiseProtocols.filter { $0.status == .open }.count
    }

    private var profileIsComplete: Bool {
        let profile = store.state.profile
        return !profile.fullName.isEmpty
            && !profile.address.street.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !profile.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var recipientIsComplete: Bool {
        store.state.properties.contains {
            $0.propertyManagementID != nil
                && !$0.reportEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var setupIsComplete: Bool {
        profileIsComplete && !store.state.properties.isEmpty && recipientIsComplete
    }

    @ViewBuilder
    private func setupRow(_ title: String, complete: Bool) -> some View {
        Label(
            title,
            systemImage: complete ? "checkmark.circle.fill" : "exclamationmark.circle"
        )
        .foregroundStyle(complete ? .green : .orange)
    }
}
