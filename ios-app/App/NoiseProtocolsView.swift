import HVMeldeCore
import PhotosUI
import SwiftUI
import UIKit
import AVKit

struct NoiseProtocolsView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var showsNewProtocol = false

    var body: some View {
        List {
            if store.state.noiseProtocols.isEmpty {
                ContentUnavailableView(
                    "Noch kein Lärmprotokoll",
                    systemImage: "waveform.badge.plus",
                    description: Text("Dokumentiere wiederkehrende Ruhestörungen über einen längeren Zeitraum.")
                )
            } else {
                protocolSection("Laufend", status: .open)
                protocolSection("Abgeschlossen", status: .completed)
            }
        }
        .navigationTitle("Lärmprotokolle")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsNewProtocol = true
                } label: {
                    Label("Neues Lärmprotokoll", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showsNewProtocol) {
            NewNoiseProtocolView()
        }
    }

    @ViewBuilder
    private func protocolSection(_ title: String, status: NoiseProtocolStatus) -> some View {
        let protocols = store.state.noiseProtocols
            .filter { $0.status == status }
            .sorted { $0.updatedAt > $1.updatedAt }
        if !protocols.isEmpty {
            Section(title) {
                ForEach(protocols) { noiseProtocol in
                    NavigationLink {
                        NoiseProtocolDetailView(protocolID: noiseProtocol.id)
                    } label: {
                        NoiseProtocolRow(noiseProtocol: noiseProtocol)
                    }
                }
            }
        }
    }
}

private struct NoiseProtocolRow: View {
    let noiseProtocol: NoiseProtocol

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: noiseProtocol.status == .open ? "waveform.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(noiseProtocol.status == .open ? .orange : .green)
            VStack(alignment: .leading, spacing: 4) {
                Text(noiseProtocol.title)
                    .font(.headline)
                Text(noiseProtocol.recipientPropertyName)
                Text("\(noiseProtocol.disturbanceCount) Vorfälle · \(noiseProtocol.interventionCount) Einsätze/Maßnahmen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let latest = noiseProtocol.lastEventAt {
                    Text("Zuletzt \(latest.formatted(date: .numeric, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct NewNoiseProtocolView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppDataStore
    @State private var selectedPropertyID: UUID?
    @State private var title = "Lärmprotokoll"
    @State private var suspectedSource = ""
    @State private var isCommonArea = false
    @State private var requestsManagementResponse = true
    @State private var allowsNameDisclosure = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Objekt") {
                    Picker("Objekt", selection: $selectedPropertyID) {
                        Text("Bitte auswählen").tag(UUID?.none)
                        ForEach(store.state.properties) { property in
                            Text(property.displayName).tag(Optional(property.id))
                        }
                    }
                    Toggle("Allgemeinfläche betroffen", isOn: $isCommonArea)
                }
                Section("Protokoll") {
                    TextField("Bezeichnung", text: $title)
                    TextField("Vermutete Lärmquelle, z. B. Top 7", text: $suspectedSource)
                    Text("Die vermutete Quelle kann leer bleiben und wird nicht als gesicherte Feststellung bezeichnet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Rückmeldung und Vertraulichkeit") {
                    Toggle("Rückmeldung der Hausverwaltung erwünscht", isOn: $requestsManagementResponse)
                    Toggle("Mein Name darf weitergegeben werden", isOn: $allowsNameDisclosure)
                }
            }
            .navigationTitle("Neues Lärmprotokoll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") {
                        guard let property else { return }
                        store.createNoiseProtocol(
                            property: property,
                            title: title,
                            suspectedSource: suspectedSource,
                            isCommonArea: isCommonArea,
                            requestsManagementResponse: requestsManagementResponse,
                            allowsNameDisclosure: allowsNameDisclosure
                        )
                        dismiss()
                    }
                    .disabled(property == nil)
                }
            }
            .onAppear {
                if selectedPropertyID == nil {
                    selectedPropertyID = store.state.properties.first?.id
                }
            }
        }
    }

    private var property: ManagedProperty? {
        guard let selectedPropertyID else { return nil }
        return store.state.properties.first { $0.id == selectedPropertyID }
    }
}

struct NoiseProtocolDetailView: View {
    @EnvironmentObject private var store: AppDataStore
    let protocolID: UUID
    @State private var showsDisturbance = false
    @State private var showsIntervention = false
    @State private var showsDeleteConfirmation = false
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var isExporting = false

    var body: some View {
        Group {
            if let noiseProtocol {
                List {
                    Section("Übersicht") {
                        LabeledContent("Objekt", value: noiseProtocol.recipientPropertyName)
                        if !noiseProtocol.suspectedSource.isEmpty {
                            LabeledContent("Vermutete Quelle", value: noiseProtocol.suspectedSource)
                        }
                        LabeledContent("Vorfälle", value: "\(noiseProtocol.disturbanceCount)")
                        LabeledContent("Einsätze/Maßnahmen", value: "\(noiseProtocol.interventionCount)")
                        LabeledContent("Beweisdateien", value: "\(noiseProtocol.evidenceFileCount)")
                        Button(noiseProtocol.status == .open ? "Protokoll abschließen" : "Protokoll wieder öffnen") {
                            store.setNoiseProtocolStatus(
                                noiseProtocol.status == .open ? .completed : .open,
                                for: protocolID
                            )
                        }
                    }

                    if noiseProtocol.status == .open {
                        Section("Neuer Eintrag") {
                            Button {
                                showsDisturbance = true
                            } label: {
                                Label("Ruhestörung erfassen", systemImage: "waveform.badge.plus")
                            }
                            Button {
                                showsIntervention = true
                            } label: {
                                Label("Einsatz oder Maßnahme erfassen", systemImage: "shield.lefthalf.filled")
                            }
                        }
                    }

                    let ongoing = noiseProtocol.entries.filter {
                        $0.kind == .disturbance && $0.endedAt == nil
                    }
                    if !ongoing.isEmpty {
                        Section("Laufende Ruhestörung") {
                            ForEach(ongoing) { entry in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(entry.noiseType.isEmpty ? "Ruhestörung" : entry.noiseType)
                                        .font(.headline)
                                    Text("Beginn: \(entry.startedAt.formatted(date: .numeric, time: .shortened))")
                                    Button("Lärm jetzt als beendet erfassen") {
                                        store.finishNoiseDisturbance(
                                            protocolID: protocolID,
                                            entryID: entry.id
                                        )
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        }
                    }

                    Section("Zeitleiste") {
                        if noiseProtocol.entries.isEmpty {
                            Text("Noch keine Einträge")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(noiseProtocol.entries.sorted { $0.startedAt > $1.startedAt }.enumerated()), id: \.element.id) { _, entry in
                            NoiseTimelineEntryRow(
                                entry: entry,
                                number: timelineNumber(for: entry, in: noiseProtocol),
                                protocolID: protocolID
                            )
                        }
                    }

                    Section("Ausgabe") {
                        Button {
                            createPDF(noiseProtocol)
                        } label: {
                            if isExporting {
                                ProgressView()
                            } else {
                                Label("Lärmprotokoll als PDF erstellen", systemImage: "doc.richtext")
                            }
                        }
                        .disabled(noiseProtocol.entries.isEmpty || isExporting)

                        Button {
                            createEvidencePackage(noiseProtocol)
                        } label: {
                            if isExporting {
                                ProgressView()
                            } else {
                                Label("Beweispaket erstellen", systemImage: "archivebox")
                            }
                        }
                        .disabled(noiseProtocol.entries.isEmpty || isExporting)

                        if let exportURL {
                            ShareLink(item: exportURL) {
                                Label("Erstellte Datei teilen", systemImage: "square.and.arrow.up")
                            }
                            DocumentExportButton(url: exportURL)
                        }
                        Text("Große Beweispakete können über Apple Mail per Mail Drop gesendet oder in iCloud Drive gespeichert und von dort als Link geteilt werden.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        Button("Lärmprotokoll löschen", role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                    }
                }
            } else {
                ContentUnavailableView("Lärmprotokoll nicht gefunden", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle(noiseProtocol?.title ?? "Lärmprotokoll")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsDisturbance) {
            NoiseDisturbanceEditor(protocolID: protocolID)
        }
        .sheet(isPresented: $showsIntervention) {
            NoiseInterventionEditor(protocolID: protocolID)
        }
        .confirmationDialog("Lärmprotokoll löschen?", isPresented: $showsDeleteConfirmation) {
            Button("Lärmprotokoll und Beweisdateien löschen", role: .destructive) {
                store.deleteNoiseProtocol(protocolID)
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Das Protokoll und alle lokal gespeicherten Videos werden endgültig entfernt.")
        }
        .alert("Ausgabe fehlgeschlagen", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "Unbekannter Fehler")
        }
    }

    private var noiseProtocol: NoiseProtocol? {
        store.state.noiseProtocols.first { $0.id == protocolID }
    }

    private func timelineNumber(for entry: NoiseTimelineEntry, in noiseProtocol: NoiseProtocol) -> String {
        let sameKind = noiseProtocol.entries
            .filter { $0.kind == entry.kind }
            .sorted { $0.startedAt < $1.startedAt }
        let index = (sameKind.firstIndex(where: { $0.id == entry.id }) ?? 0) + 1
        return "\(entry.kind == .disturbance ? "L" : "E")-\(String(format: "%03d", index))"
    }

    private func createPDF(_ noiseProtocol: NoiseProtocol) {
        isExporting = true
        exportURL = nil
        do {
            exportURL = try NoiseProtocolPDFRenderer.render(
                noiseProtocol: noiseProtocol,
                profile: store.state.profile,
                management: store.state.propertyManagements.first {
                    store.state.properties.first(where: { $0.id == noiseProtocol.propertyID })?
                        .propertyManagementID == $0.id
                },
                evidenceURL: { store.noiseEvidenceURL(for: $0, protocolID: protocolID) }
            )
        } catch {
            exportError = error.localizedDescription
        }
        isExporting = false
    }

    private func createEvidencePackage(_ noiseProtocol: NoiseProtocol) {
        isExporting = true
        exportURL = nil
        Task {
            do {
                let url = try await NoiseEvidencePackageExporter.create(
                    noiseProtocol: noiseProtocol,
                    profile: store.state.profile,
                    management: store.state.propertyManagements.first {
                        store.state.properties.first(where: { $0.id == noiseProtocol.propertyID })?
                            .propertyManagementID == $0.id
                    },
                    evidenceURL: { store.noiseEvidenceURL(for: $0, protocolID: protocolID) }
                )
                await MainActor.run {
                    exportURL = url
                    isExporting = false
                }
            } catch {
                await MainActor.run {
                    exportError = error.localizedDescription
                    isExporting = false
                }
            }
        }
    }
}

private struct NoiseTimelineEntryRow: View {
    @EnvironmentObject private var store: AppDataStore
    let entry: NoiseTimelineEntry
    let number: String
    let protocolID: UUID
    @State private var playback: EvidencePlayback?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(number)
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(.secondary)
                Text(entry.kind.rawValue)
                    .font(.headline)
            }
            Text(entry.startedAt.formatted(date: .numeric, time: .shortened))
            if let endedAt = entry.endedAt {
                Text("bis \(endedAt.formatted(date: .numeric, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if entry.kind == .disturbance {
                if !entry.noiseType.isEmpty { Text(entry.noiseType) }
                if !entry.impact.isEmpty {
                    Text(entry.impact)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                if !entry.responderType.isEmpty { Text(entry.responderType) }
                if !entry.referenceNumber.isEmpty {
                    Text("Einsatz-/Aktennummer: \(entry.referenceNumber)")
                        .font(.caption)
                }
            }
            if !entry.details.isEmpty {
                Text(entry.details)
                    .font(.caption)
            }
            if !entry.evidenceFiles.isEmpty {
                Label("\(entry.evidenceFiles.count) Beweisdateien", systemImage: "paperclip")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(entry.evidenceFiles) { evidence in
                    if let url = store.noiseEvidenceURL(for: evidence, protocolID: protocolID) {
                        Button {
                            playback = EvidencePlayback(url: url, title: evidence.originalFileName)
                        } label: {
                            Label(evidence.originalFileName, systemImage: "play.rectangle")
                        }
                        .buttonStyle(.borderless)
                    } else {
                        Label("\(evidence.originalFileName) – nur auf dem Aufnahmegerät verfügbar", systemImage: "exclamationmark.icloud")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .sheet(item: $playback) { item in
            EvidenceVideoPlayerView(item: item)
        }
    }
}

private struct EvidencePlayback: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

private struct EvidenceVideoPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    let item: EvidencePlayback
    @State private var player: AVPlayer

    init(item: EvidencePlayback) {
        self.item = item
        _player = State(initialValue: AVPlayer(url: item.url))
    }

    var body: some View {
        NavigationStack {
            VideoPlayer(player: player)
                .background(Color.black)
                .navigationTitle(item.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { dismiss() }
                    }
                }
                .onAppear { player.play() }
                .onDisappear { player.pause() }
        }
    }
}

private struct NoiseDisturbanceEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppDataStore
    let protocolID: UUID
    @State private var entryID = UUID()
    @State private var startedAt = Date()
    @State private var endedAt = Date()
    @State private var isOngoing = true
    @State private var noiseType = "Musik oder Bass"
    @State private var sourceLocation = ""
    @State private var perceivedLocation = ""
    @State private var impact = ""
    @State private var details = ""
    @State private var witnesses = ""
    @State private var evidenceFiles: [NoiseEvidenceFile] = []
    @State private var selectedVideos: [PhotosPickerItem] = []
    @State private var showsCamera = false
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var didSave = false

    private let noiseSuggestions = [
        "Musik oder Bass", "Stimmen oder Schreien", "Stampfen oder Klopfen",
        "Möbelrücken", "Tierlärm", "Bauarbeiten", "Maschinen oder Geräte", "Sonstiges"
    ]
    private let impactSuggestions = [
        "Aufgewacht", "Einschlafen nicht möglich", "Schlaf erheblich beeinträchtigt",
        "Gespräch oder Arbeit beeinträchtigt", "In mehreren Räumen deutlich hörbar"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Zeit") {
                    DatePicker("Beginn", selection: $startedAt)
                    Toggle("Lärm dauert noch an", isOn: $isOngoing)
                    if !isOngoing {
                        DatePicker("Ende", selection: $endedAt, in: startedAt...)
                    }
                    Text("Beginn und Ende beschreiben den gesamten Vorfall. Die Videodauer ist nur die Länge der Beweisaufnahme.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Wahrnehmung") {
                    Picker("Art der Ruhestörung", selection: $noiseType) {
                        ForEach(noiseSuggestions, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Vermutete Quelle oder Wohnung", text: $sourceLocation)
                    TextField("Wahrgenommen in, z. B. Schlafzimmer", text: $perceivedLocation)
                    Menu {
                        ForEach(impactSuggestions, id: \.self) { suggestion in
                            Button(suggestion) { impact = suggestion }
                        }
                    } label: {
                        LabeledContent("Auswirkung", value: impact.isEmpty ? "Auswählen" : impact)
                    }
                    TextField("Auswirkung ergänzen", text: $impact, axis: .vertical)
                    TextField("Sachliche Beschreibung", text: $details, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("Zeugen", text: $witnesses)
                }
                evidenceSection
            }
            .navigationTitle("Ruhestörung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        didSave = true
                        store.addNoiseEntry(
                            NoiseTimelineEntry(
                                id: entryID,
                                kind: .disturbance,
                                startedAt: startedAt,
                                endedAt: isOngoing ? nil : max(startedAt, endedAt),
                                noiseType: noiseType,
                                sourceLocation: sourceLocation,
                                perceivedLocation: perceivedLocation,
                                impact: impact,
                                details: details,
                                witnesses: witnesses,
                                evidenceFiles: evidenceFiles
                            ),
                            to: protocolID
                        )
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $showsCamera) {
                VideoCameraPickerView { url in
                    showsCamera = false
                    importVideo(url: url, originalFileName: "Kameraaufnahme.mov", removeSourceAfterward: false)
                } onCancel: {
                    showsCamera = false
                }
                .ignoresSafeArea()
            }
            .onChange(of: selectedVideos) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    isImporting = true
                    for item in items {
                        do {
                            guard let video = try await item.loadTransferable(type: ImportedEvidenceVideo.self) else {
                                continue
                            }
                            let evidence = try await NoiseEvidenceStore.storeVideo(
                                from: video.url,
                                protocolID: protocolID,
                                entryID: entryID,
                                originalFileName: video.url.lastPathComponent
                            )
                            evidenceFiles.append(evidence)
                            try? FileManager.default.removeItem(at: video.url)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    selectedVideos = []
                    isImporting = false
                }
            }
            .onDisappear {
                if !didSave {
                    try? NoiseEvidenceStore.removeDraftEvidence(protocolID: protocolID, entryID: entryID)
                }
            }
            .alert("Video konnte nicht übernommen werden", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unbekannter Fehler")
            }
        }
    }

    @ViewBuilder
    private var evidenceSection: some View {
        Section("Video- und Tonbelege") {
            Text("Nimm nur den konkreten Vorfall auf. Verständliche Gespräche oder unbeteiligte Personen können rechtlich besonders sensibel sein.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showsCamera = true
                } label: {
                    Label("Video mit Ton aufnehmen", systemImage: "video.badge.plus")
                }
            }
            PhotosPicker(
                selection: $selectedVideos,
                maxSelectionCount: 5,
                matching: .videos
            ) {
                Label("Vorhandene Videos auswählen", systemImage: "photo.on.rectangle")
            }
            if isImporting {
                HStack {
                    ProgressView()
                    Text("Video wird beweissicher übernommen …")
                }
            }
            ForEach(evidenceFiles) { evidence in
                VStack(alignment: .leading, spacing: 3) {
                    Text(evidence.originalFileName)
                    Text("\(ByteCountFormatter.string(fromByteCount: evidence.byteCount, countStyle: .file)) · SHA-256 \(evidence.sha256.prefix(12))…")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Button("Entfernen", role: .destructive) {
                        try? NoiseEvidenceStore.removeEvidence(evidence, protocolID: protocolID)
                        evidenceFiles.removeAll { $0.id == evidence.id }
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func importVideo(url: URL, originalFileName: String, removeSourceAfterward: Bool) {
        isImporting = true
        Task {
            do {
                let evidence = try await NoiseEvidenceStore.storeVideo(
                    from: url,
                    protocolID: protocolID,
                    entryID: entryID,
                    originalFileName: originalFileName
                )
                evidenceFiles.append(evidence)
                if removeSourceAfterward { try? FileManager.default.removeItem(at: url) }
            } catch {
                errorMessage = error.localizedDescription
            }
            isImporting = false
        }
    }
}

private struct NoiseInterventionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppDataStore
    let protocolID: UUID
    @State private var notifiedAt = Date()
    @State private var hasArrival = false
    @State private var arrivedAt = Date()
    @State private var hasDeparture = false
    @State private var departedAt = Date()
    @State private var responderType = "Polizei"
    @State private var stationOrUnit = ""
    @State private var officers = ""
    @State private var referenceNumber = ""
    @State private var outcome = ""
    @State private var details = ""

    private let responderSuggestions = [
        "Polizei", "Gemeinde- oder Ortspolizei", "Sicherheitsdienst",
        "Feuerwehr", "Rettung", "Hausverwaltung oder Hausmeister", "Sonstige"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Zeit") {
                    DatePicker("Verständigt am", selection: $notifiedAt)
                    Toggle("Eintreffen dokumentieren", isOn: $hasArrival)
                    if hasArrival {
                        DatePicker("Eingetroffen", selection: $arrivedAt, in: notifiedAt...)
                    }
                    Toggle("Einsatzende dokumentieren", isOn: $hasDeparture)
                    if hasDeparture {
                        DatePicker("Einsatz beendet", selection: $departedAt)
                    }
                }
                Section("Einsatzkräfte") {
                    Menu {
                        ForEach(responderSuggestions, id: \.self) { value in
                            Button(value) { responderType = value }
                        }
                    } label: {
                        LabeledContent("Art", value: responderType)
                    }
                    TextField("Art frei eingeben", text: $responderType)
                    TextField("Dienststelle oder Einheit", text: $stationOrUnit)
                    TextField("Namen und Dienstnummern", text: $officers, axis: .vertical)
                        .lineLimit(2...6)
                    TextField("Einsatz- oder Aktennummer", text: $referenceNumber)
                }
                Section("Ergebnis") {
                    TextField("Getroffene Maßnahmen und Ergebnis", text: $outcome, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("Weitere sachliche Angaben", text: $details, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle("Einsatz oder Maßnahme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        store.addNoiseEntry(
                            NoiseTimelineEntry(
                                kind: .intervention,
                                startedAt: notifiedAt,
                                endedAt: hasDeparture ? departedAt : nil,
                                details: details,
                                notifiedAt: notifiedAt,
                                arrivedAt: hasArrival ? arrivedAt : nil,
                                departedAt: hasDeparture ? departedAt : nil,
                                responderType: responderType,
                                stationOrUnit: stationOrUnit,
                                officers: officers,
                                referenceNumber: referenceNumber,
                                outcome: outcome
                            ),
                            to: protocolID
                        )
                        dismiss()
                    }
                    .disabled(responderType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct DocumentExportButton: View {
    let url: URL
    @State private var showsExporter = false

    var body: some View {
        Button {
            showsExporter = true
        } label: {
            Label("In Dateien oder iCloud Drive sichern", systemImage: "icloud.and.arrow.up")
        }
        .sheet(isPresented: $showsExporter) {
            DocumentExporterView(url: url)
        }
    }
}

private struct DocumentExporterView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            dismiss()
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            dismiss()
        }
    }
}
