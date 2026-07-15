import Foundation
import HVMeldeCore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PhotoAnalysisSection: View {
    @EnvironmentObject private var store: AppDataStore
    let reportID: UUID
    let category: ReportCategory
    @Binding var evidencePhotos: [EvidencePhoto]
    @Binding var licensePlate: String
    @Binding var vehicleDescription: String
    @Binding var notes: String

    @State private var selectedItem: PhotosPickerItem?
    @State private var reviewTarget: ImageAnalysisReviewTarget?
    @State private var analysisResults: [UUID: LocalImageAnalysis] = [:]
    @State private var analyzingPhotoID: UUID?
    @State private var isAnalyzing = false
    @State private var isImporting = false
    @State private var showsCamera = false
    @State private var errorMessage: String?
    @State private var importTask: Task<Void, Never>?

    var body: some View {
        Section("Foto und lokale Erkennung") {
            PhotosPicker(
                selection: $selectedItem,
                matching: .images,
                preferredItemEncoding: .compatible
            ) {
                Label(
                    evidencePhotos.isEmpty ? "Foto auswählen" : "Weiteres Foto auswählen",
                    systemImage: "photo"
                )
            }
            .disabled(isImporting || isAnalyzing || evidencePhotos.count >= 10)

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showsCamera = true
                } label: {
                    Label("Foto aufnehmen", systemImage: "camera")
                }
                .disabled(isImporting || isAnalyzing || evidencePhotos.count >= 10)
            }

            if isImporting {
                HStack {
                    ProgressView()
                    Text("Originalfoto wird lokal gesichert …")
                    Spacer()
                    Button("Abbrechen", role: .cancel) {
                        importTask?.cancel()
                        importTask = nil
                        isImporting = false
                    }
                }
            }

            if evidencePhotos.count >= 10 {
                Label("Maximal zehn Beweisfotos erreicht", systemImage: "photo.stack")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(evidencePhotos.enumerated()), id: \.element.id) { index, photo in
                VStack(alignment: .leading, spacing: 10) {
                    if let image = UIImage(data: photo.data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .accessibilityLabel("Beweisfoto \(index + 1)")
                    }

                    Text("Beweisfoto \(index + 1)")
                        .font(.headline)
                    DisclosureGroup("Technische Angaben") {
                        evidenceDetails(photo)
                    }

                    HStack {
                        Button {
                            analyze(photo)
                        } label: {
                            if analyzingPhotoID == photo.id {
                                ProgressView()
                            } else {
                                Label(
                                    photo.confirmedAnalysis == nil ? "Analysieren" : "Erneut analysieren",
                                    systemImage: "sparkles"
                                )
                            }
                        }
                        .disabled(isAnalyzing)

                        Spacer()

                        Button(role: .destructive) {
                            remove(photo)
                        } label: {
                            Label("Entfernen", systemImage: "trash")
                        }
                        .disabled(isAnalyzing || isImporting)
                    }

                    if let result = analysisResults[photo.id] {
                        Button {
                            reviewTarget = ImageAnalysisReviewTarget(
                                photoID: photo.id,
                                analysis: result
                            )
                        } label: {
                            Label("Erkannte Werte prüfen und übernehmen", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            if store.state.preferences.enhancedLocalAnalysisEnabled {
                Label(
                    LocalIntelligenceService.availability.settingsDescription,
                    systemImage: "sparkles"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text("Bis zu zehn Originalfotos werden geschützt auf diesem Gerät gespeichert und verlassen es nicht automatisch. Erkennungen sind Vorschläge und werden erst nach deiner Bestätigung übernommen.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            selectedItem = nil
            importTask?.cancel()
            importTask = Task { await loadImage(from: newItem) }
        }
        .onChange(of: category) { _, _ in
            reviewTarget = nil
            analysisResults = [:]
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPickerView { data in
                showsCamera = false
                Task { await storeImage(data, source: .camera, fileExtension: "jpg") }
            } onCancel: {
                showsCamera = false
            }
            .ignoresSafeArea()
        }
        .sheet(item: $reviewTarget) { target in
            ImageAnalysisReviewView(
                analysis: target.analysis,
                currentLicensePlate: licensePlate,
                currentVehicleDescription: vehicleDescription
            ) { confirmedPlate, confirmedVehicle, confirmedSummary in
                applyConfirmation(
                    target.analysis,
                    photoID: target.photoID,
                    plate: confirmedPlate,
                    vehicle: confirmedVehicle,
                    summary: confirmedSummary
                )
            }
        }
        .alert("Bildverarbeitung fehlgeschlagen", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unbekannter Fehler")
        }
        .onDisappear {
            importTask?.cancel()
            importTask = nil
        }
    }

    @ViewBuilder
    private func evidenceDetails(_ photo: EvidencePhoto) -> some View {
        LabeledContent("Quelle", value: photo.source.rawValue)
        if let capturedAt = photo.imageTimestamp.capturedAt {
            LabeledContent("Bild aufgenommen") {
                Text(capturedAt, format: .dateTime.day().month().year().hour().minute().second())
            }
            if !photo.imageTimestamp.timeZoneWasEmbedded,
               let timeZone = photo.imageTimestamp.interpretedTimeZone {
                Text("Die Bilddatei enthält keine Zeitzone; die Aufnahmezeit wurde als \(timeZone) interpretiert.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } else {
            LabeledContent("Bild aufgenommen", value: "Nicht in Metadaten enthalten")
        }
        LabeledContent("In App übernommen") {
            Text(photo.importedAt, format: .dateTime.day().month().year().hour().minute().second())
        }
        LabeledContent("SHA-256") {
            Text(String(photo.sha256.prefix(16)) + "…")
                .font(.caption.monospaced())
        }
        if photo.confirmedAnalysis != nil {
            Label("Erkennung wurde geprüft und bestätigt", systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    @MainActor
    private func loadImage(from item: PhotosPickerItem) async {
        isImporting = true
        defer {
            isImporting = false
            importTask = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw PhotoAnalysisError.imageCouldNotBeLoaded
            }
            try Task.checkCancellation()
            let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension
            try await storeLoadedImage(data, source: .photoLibrary, fileExtension: fileExtension)
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func storeImage(
        _ data: Data,
        source: EvidencePhotoSource,
        fileExtension: String?
    ) async {
        isImporting = true
        defer { isImporting = false }
        do {
            try await storeLoadedImage(data, source: source, fileExtension: fileExtension)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func storeLoadedImage(
        _ data: Data,
        source: EvidencePhotoSource,
        fileExtension: String?
    ) async throws {
        let evidencePhoto = try await EvidencePhotoStore.store(
            data: data,
            reportID: reportID,
            source: source,
            fileExtension: fileExtension
        )
        evidencePhotos.append(evidencePhoto)
        reviewTarget = nil
        errorMessage = nil
    }

    private func analyze(_ photo: EvidencePhoto) {
        isAnalyzing = true
        analyzingPhotoID = photo.id
        errorMessage = nil
        let useEnhancedLocalAnalysis = store.state.preferences.enhancedLocalAnalysisEnabled
        Task {
            do {
                let result = try await LocalImageAnalyzer.analyze(
                    imageData: photo.data,
                    category: category,
                    useEnhancedLocalAnalysis: useEnhancedLocalAnalysis
                )
                await MainActor.run {
                    analysisResults[photo.id] = result
                    isAnalyzing = false
                    analyzingPhotoID = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isAnalyzing = false
                    analyzingPhotoID = nil
                }
            }
        }
    }

    private func applyConfirmation(
        _ result: LocalImageAnalysis,
        photoID: UUID,
        plate: String,
        vehicle: String,
        summary: String
    ) {
        if !plate.isEmpty { licensePlate = plate }
        if !vehicle.isEmpty { vehicleDescription = vehicle }
        if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes = summary
        }

        guard let index = evidencePhotos.firstIndex(where: { $0.id == photoID }) else { return }
        var photo = evidencePhotos[index]
        photo.confirmedAnalysis = ConfirmedImageAnalysis(
            category: result.category,
            vehicleDetected: result.vehicle.detected,
            vehicleConfidence: result.vehicle.confidence,
            suggestedVehicleType: result.category.expectsVehicle ? result.vehicleType?.name : nil,
            suggestedVehicleTypeConfidence: result.category.expectsVehicle ? result.vehicleType?.confidence : nil,
            suggestedVehicleColor: result.category.expectsVehicle ? result.vehicleColor?.name : nil,
            suggestedVehicleColorConfidence: result.category.expectsVehicle ? result.vehicleColor?.confidence : nil,
            suggestedSceneObjects: result.relevantObjects.map {
                ImageAnalysisObjectRecord(name: $0.name, confidence: $0.confidence)
            },
            confirmedLicensePlate: plate,
            confirmedVehicleDescription: vehicle,
            confirmedSceneSummary: summary,
            analyzedAt: Date(),
            analyzerDescription: result.localIntelligenceOutcome == .applied
                ? "Apple Vision mit lokaler Apple-Intelligence-Formulierung; heuristische Farbauswertung"
                : "Apple Vision: Bildklassifizierung, Texterkennung und Salienz; lokale heuristische Farbauswertung"
        )
        evidencePhotos[index] = photo
        Task {
            do {
                try await EvidencePhotoStore.updateMetadata(for: photo)
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    private func remove(_ photo: EvidencePhoto) {
        Task {
            do {
                try await EvidencePhotoStore.delete(photo)
                await MainActor.run {
                    evidencePhotos.removeAll { $0.id == photo.id }
                    analysisResults[photo.id] = nil
                    if reviewTarget?.photoID == photo.id { reviewTarget = nil }
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
}

private struct ImageAnalysisReviewTarget: Identifiable {
    let photoID: UUID
    let analysis: LocalImageAnalysis
    var id: UUID { analysis.id }
}

private enum PhotoAnalysisError: LocalizedError {
    case imageCouldNotBeLoaded

    var errorDescription: String? {
        "Das ausgewählte Foto konnte nicht geladen werden."
    }
}

private struct ImageAnalysisReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let analysis: LocalImageAnalysis
    let onConfirm: (String, String, String) -> Void

    @State private var licensePlate: String
    @State private var vehicleDescription: String
    @State private var sceneSummary: String

    init(
        analysis: LocalImageAnalysis,
        currentLicensePlate: String,
        currentVehicleDescription: String,
        onConfirm: @escaping (String, String, String) -> Void
    ) {
        self.analysis = analysis
        self.onConfirm = onConfirm
        _licensePlate = State(initialValue: analysis.plateCandidates.first?.text ?? currentLicensePlate)
        _vehicleDescription = State(
            initialValue: currentVehicleDescription.isEmpty && analysis.vehicle.detected
                ? analysis.suggestedVehicleDescription
                : currentVehicleDescription
        )
        _sceneSummary = State(initialValue: analysis.sceneSummary)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Gewählte Kategorie") {
                    Text(analysis.category.rawValue)
                }

                if analysis.category.expectsVehicle {
                    Section("Fahrzeug") {
                    LabeledContent("Erkannt") {
                        Label(
                            analysis.vehicle.detected ? "Ja" : "Unsicher",
                            systemImage: analysis.vehicle.detected ? "checkmark.circle.fill" : "questionmark.circle"
                        )
                        .foregroundStyle(analysis.vehicle.detected ? .green : .orange)
                    }
                    LabeledContent("Konfidenz", value: analysis.vehicle.confidence, format: .percent.precision(.fractionLength(0)))
                    if let vehicleType = analysis.vehicleType {
                        LabeledContent("Vorgeschlagener Typ") {
                            VStack(alignment: .trailing) {
                                Text(vehicleType.name)
                                Text(vehicleType.confidence, format: .percent.precision(.fractionLength(0)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let vehicleColor = analysis.vehicleColor {
                        LabeledContent("Geschätzte Farbe") {
                            VStack(alignment: .trailing) {
                                Text(vehicleColor.name)
                                Text(vehicleColor.confidence, format: .percent.precision(.fractionLength(0)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text("Die Farbe wird aus dem auffälligen Bildbereich berechnet und kann durch Licht, Schatten oder Hintergrund verfälscht sein.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    TextField("Bestätigte Fahrzeugbeschreibung", text: $vehicleDescription)
                    }

                    Section("Kennzeichen") {
                        TextField("Kennzeichen prüfen", text: $licensePlate)
                            .textInputAutocapitalization(.characters)
                        ForEach(analysis.plateCandidates.dropFirst()) { candidate in
                            Button("Alternative übernehmen: \(candidate.text)") {
                                licensePlate = candidate.text
                            }
                        }
                        if analysis.plateCandidates.isEmpty {
                            Text("Kein plausibles Kennzeichen erkannt.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Beschreibungsvorschlag") {
                    TextField("Beschreibung", text: $sceneSummary, axis: .vertical)
                        .lineLimit(3...8)
                }

                if let description = analysis.localIntelligenceOutcome.description {
                    Section("Erweiterte lokale Analyse") {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !analysis.relevantObjects.isEmpty {
                    Section("Weitere mögliche Objekte") {
                        ForEach(analysis.relevantObjects) { object in
                            LabeledContent(object.name, value: object.confidence, format: .percent.precision(.fractionLength(0)))
                        }
                        Text("Auch diese Treffer sind nur Vorschläge. Übernimm sie nur, wenn sie auf dem Originalfoto eindeutig sichtbar sind.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Technische Nachvollziehbarkeit") {
                    LabeledContent("Bild-Prüfsumme") {
                        Text(String(analysis.imageSHA256.prefix(16)) + "…")
                            .font(.caption.monospaced())
                    }
                    DisclosureGroup("Vision-Klassifikationen") {
                        ForEach(Array(analysis.classifications.prefix(8)), id: \.identifier) { label in
                            LabeledContent(label.identifier, value: label.confidence, format: .percent.precision(.fractionLength(0)))
                        }
                    }
                }

                Section {
                    Text("Bitte bestätige nur Angaben, die du selbst am Originalfoto nachvollziehen kannst.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Erkennung prüfen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") {
                        onConfirm(licensePlate, vehicleDescription, sceneSummary)
                        dismiss()
                    }
                }
            }
        }
    }
}
