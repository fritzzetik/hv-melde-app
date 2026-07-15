import HVMeldeCore
import SwiftUI

struct ReportedCasesView: View {
    @EnvironmentObject private var store: AppDataStore

    var body: some View {
        List {
            if store.state.reportedCases.isEmpty {
                ContentUnavailableView(
                    "Noch keine Fälle",
                    systemImage: "tray",
                    description: Text("Erzeugte PDF-Meldungen werden automatisch hier gespeichert.")
                )
            } else {
                caseSection("Offen", cases: cases(with: .open))
                caseSection("Erledigt", cases: cases(with: .completed))
            }
        }
        .navigationTitle("Gemeldete Fälle")
        .alert("Speichern fehlgeschlagen", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "Unbekannter Fehler")
        }
    }

    @ViewBuilder
    private func caseSection(_ title: String, cases: [StoredReportedCase]) -> some View {
        if !cases.isEmpty {
            Section(title) {
                ForEach(cases) { reportedCase in
                    NavigationLink {
                        ReportedCaseDetailView(caseID: reportedCase.id)
                    } label: {
                        ReportedCaseRow(reportedCase: reportedCase)
                    }
                    .swipeActions(edge: .trailing) {
                        if reportedCase.status == .open {
                            Button {
                                store.setCaseStatus(.completed, for: reportedCase.id)
                            } label: {
                                Label("Erledigt", systemImage: "checkmark")
                            }
                            .tint(.green)
                        } else {
                            Button {
                                store.setCaseStatus(.open, for: reportedCase.id)
                            } label: {
                                Label("Wieder öffnen", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
        }
    }

    private func cases(with status: ReportedCaseStatus) -> [StoredReportedCase] {
        store.state.reportedCases
            .filter { $0.status == status }
            .sorted { $0.incidentAt > $1.incidentAt }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.clearError() } }
        )
    }
}

private struct ReportedCaseRow: View {
    let reportedCase: StoredReportedCase

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: reportedCase.status == .completed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(reportedCase.status == .completed ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(reportedCase.category.rawValue)
                    .font(.headline)
                Text(reportedCase.propertyName)
                Text(reportedCase.concernsCommonArea ? "Allgemeinfläche" : reportedCase.occupancyRole.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(reportedCase.incidentAt, format: .dateTime.day().month().year().hour().minute())
                    if !reportedCase.licensePlate.isEmpty {
                        Text("· \(reportedCase.licensePlate)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ReportedCaseDetailView: View {
    @EnvironmentObject private var store: AppDataStore
    let caseID: UUID

    var body: some View {
        Group {
            if let reportedCase {
                Form {
                    Section("Status") {
                        LabeledContent("Status", value: reportedCase.status.rawValue)
                        Button(reportedCase.status == .open ? "Als erledigt markieren" : "Fall wieder öffnen") {
                            store.setCaseStatus(
                                reportedCase.status == .open ? .completed : .open,
                                for: reportedCase.id
                            )
                        }
                        if let completedAt = reportedCase.completedAt {
                            LabeledContent("Erledigt am") {
                                Text(completedAt, format: .dateTime.day().month().year().hour().minute())
                            }
                        }
                    }

                    Section("Fall") {
                        LabeledContent("Meldungs-ID", value: reportedCase.id.uuidString)
                        LabeledContent("Kategorie", value: reportedCase.category.rawValue)
                        LabeledContent("Beobachtet") {
                            Text(reportedCase.incidentAt, format: .dateTime.day().month().year().hour().minute())
                        }
                        LabeledContent("Erstellt") {
                            Text(reportedCase.createdAt, format: .dateTime.day().month().year().hour().minute())
                        }
                    }

                    Section("Objekt") {
                        LabeledContent("Objekt", value: reportedCase.propertyName)
                        LabeledContent("Rolle", value: reportedCase.occupancyRole.rawValue)
                        LabeledContent(
                            "Bezug der Meldung",
                            value: reportedCase.concernsCommonArea
                                ? "Allgemeinfläche"
                                : (reportedCase.occupancyRole == .tenant ? "Gemietetes Objekt" : "Objekt im Eigentum")
                        )
                        Text(reportedCase.propertyAddress.formatted)
                        if !reportedCase.garageLocation.isEmpty {
                            LabeledContent("Bereich", value: reportedCase.garageLocation)
                        }
                    }

                    Section("Dokumentation") {
                        if !reportedCase.licensePlate.isEmpty {
                            LabeledContent("Kennzeichen", value: reportedCase.licensePlate)
                        }
                        if !reportedCase.vehicleDescription.isEmpty {
                            detail("Fahrzeug", value: reportedCase.vehicleDescription)
                        }
                        detail("Verstoß", value: reportedCase.violation)
                        if !reportedCase.notes.isEmpty {
                            detail("Beschreibung", value: reportedCase.notes)
                        }
                        if !reportedCase.witnesses.isEmpty {
                            detail("Zeugen", value: reportedCase.witnesses)
                        }
                        if let hash = reportedCase.evidenceSHA256 {
                            detail("SHA-256 des Beweisfotos", value: hash, monospaced: true)
                        }
                    }

                    if let pdfURL = store.pdfURL(for: reportedCase) {
                        Section("PDF") {
                            ShareLink(item: pdfURL) {
                                Label("Gespeichertes PDF teilen", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("Fall nicht gefunden", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle("Falldetails")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var reportedCase: StoredReportedCase? {
        store.state.reportedCases.first { $0.id == caseID }
    }

    @ViewBuilder
    private func detail(_ label: String, value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .caption.monospaced() : .body)
                .textSelection(.enabled)
        }
    }
}
