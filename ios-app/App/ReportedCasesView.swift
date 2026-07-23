import HVMeldeCore
import SwiftUI

struct ReportedCasesView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var casePendingDeletion: StoredReportedCase?

    var body: some View {
        List {
            Section {
                NavigationLink {
                    NoiseProtocolsView()
                } label: {
                    LabeledContent(
                        "Lärmprotokolle",
                        value: "\(store.state.noiseProtocols.filter { $0.status == .open }.count) laufend"
                    )
                }
            }
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
        .confirmationDialog(
            "Meldung löschen?",
            isPresented: deletionIsPresented,
            titleVisibility: .visible
        ) {
            Button("Meldung endgültig löschen", role: .destructive) {
                guard let reportedCase = casePendingDeletion else { return }
                store.deleteReportedCase(reportedCase.id)
                casePendingDeletion = nil
            }
            Button("Abbrechen", role: .cancel) {
                casePendingDeletion = nil
            }
        } message: {
            Text("Der Fall, das gespeicherte PDF und die lokalen Beweisdateien werden von diesem Gerät entfernt.")
        }
        .alert("Aktion fehlgeschlagen", isPresented: errorIsPresented) {
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
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            casePendingDeletion = reportedCase
                        } label: {
                            Label("Löschen", systemImage: "trash")
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

    private var deletionIsPresented: Binding<Bool> {
        Binding(
            get: { casePendingDeletion != nil },
            set: { if !$0 { casePendingDeletion = nil } }
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
                if reportedCase.recipientPropertyName != reportedCase.propertyName {
                    Text(reportedCase.recipientPropertyName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
    @State private var mailDraft: MailDraft?

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
                        LabeledContent("Interner Name", value: reportedCase.propertyName)
                        if reportedCase.recipientPropertyName != reportedCase.propertyName {
                            LabeledContent("Offizielle Bezeichnung", value: reportedCase.recipientPropertyName)
                        }
                        LabeledContent("Objekttyp", value: reportedCase.resolvedPropertyType.rawValue)
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
                            detail("SHA-256 der Beweisfotos", value: hash, monospaced: true)
                        }
                    }

                    Section("Rückmeldung und Vertraulichkeit") {
                        LabeledContent(
                            "Rückmeldung der Hausverwaltung",
                            value: reportedCase.wantsManagementResponse ? "Erwünscht" : "Nicht erforderlich"
                        )
                        LabeledContent(
                            "Weitergabe des Namens",
                            value: reportedCase.permitsNameDisclosure ? "Erlaubt" : "Nicht erlaubt"
                        )
                    }

                    if let pdfURL = store.pdfURL(for: reportedCase) {
                        Section("PDF") {
                            Button {
                                mailDraft = copyMailDraft(for: reportedCase, pdfURL: pdfURL)
                            } label: {
                                Label("PDF erneut per Mail senden", systemImage: "envelope")
                            }
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
        .sheet(item: $mailDraft) { draft in
            MailComposerView(draft: draft)
        }
    }

    private var reportedCase: StoredReportedCase? {
        store.state.reportedCases.first { $0.id == caseID }
    }

    private func copyMailDraft(for reportedCase: StoredReportedCase, pdfURL: URL) -> MailDraft {
        let recipient = store.state.properties
            .first(where: { $0.id == reportedCase.propertyID })?
            .reportEmail
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var details = [reportedCase.garageLocation.trimmingCharacters(in: .whitespacesAndNewlines)]
            .filter { !$0.isEmpty }
        if !reportedCase.licensePlate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            details.append("Kennzeichen \(reportedCase.licensePlate)")
        }
        if details.isEmpty {
            let summary = reportedCase.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            details.append(summary.isEmpty ? "Details siehe PDF" : String(summary.prefix(60)))
        }

        let subject = "\(reportedCase.recipientPropertyName) - \(reportedCase.violation) - \(details.joined(separator: ", ")) - (KOPIE)"
        return MailDraft(
            recipients: recipient.map { [$0] } ?? [],
            subject: subject,
            body: "Anbei übermittle ich erneut eine Kopie der bereits erstellten Meldung.",
            attachmentURL: pdfURL,
            additionalAttachmentURLs: store.technicalJSONURL(for: reportedCase).map { [$0] } ?? []
        )
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
