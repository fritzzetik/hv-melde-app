import Foundation
import HVMeldeCore
import PhotosUI
import SwiftUI
import UIKit

struct PhotoAnalysisSection: View {
    let category: ReportCategory
    @Binding var licensePlate: String
    @Binding var vehicleDescription: String
    @Binding var notes: String

    @State private var selectedItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var analysis: LocalImageAnalysis?
    @State private var reviewAnalysis: LocalImageAnalysis?
    @State private var isAnalyzing = false
    @State private var errorMessage: String?

    var body: some View {
        Section("Foto und lokale Erkennung") {
            PhotosPicker(selection: $selectedItem, matching: .images) {
                Label(imageData == nil ? "Foto auswählen" : "Anderes Foto auswählen", systemImage: "photo")
            }

            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Ausgewähltes Beweisfoto")

                Button {
                    analyze(imageData)
                } label: {
                    if isAnalyzing {
                        HStack {
                            ProgressView()
                            Text("Wird lokal analysiert …")
                        }
                    } else {
                        Label("Foto lokal analysieren", systemImage: "sparkles")
                    }
                }
                .disabled(isAnalyzing)
            }

            if let analysis {
                Button {
                    reviewAnalysis = analysis
                } label: {
                    Label("Erkennung prüfen und übernehmen", systemImage: "checkmark.circle")
                }
            }

            Text("Das Foto verlässt das Gerät nicht. Erkennungen sind Vorschläge und werden erst nach deiner Bestätigung übernommen.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadImage(from: newItem) }
        }
        .onChange(of: category) { _, _ in
            analysis = nil
            reviewAnalysis = nil
        }
        .sheet(item: $reviewAnalysis) { result in
            ImageAnalysisReviewView(
                analysis: result,
                currentLicensePlate: licensePlate,
                currentVehicleDescription: vehicleDescription
            ) { confirmedPlate, confirmedVehicle, confirmedSummary in
                if !confirmedPlate.isEmpty {
                    licensePlate = confirmedPlate
                }
                if !confirmedVehicle.isEmpty {
                    vehicleDescription = confirmedVehicle
                }
                if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    notes = confirmedSummary
                }
            }
        }
        .alert("Bildanalyse fehlgeschlagen", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unbekannter Fehler")
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
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw PhotoAnalysisError.imageCouldNotBeLoaded
            }
            imageData = data
            analysis = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func analyze(_ data: Data) {
        isAnalyzing = true
        errorMessage = nil
        Task {
            do {
                let result = try await LocalImageAnalyzer.analyze(imageData: data, category: category)
                await MainActor.run {
                    analysis = result
                    reviewAnalysis = result
                    isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isAnalyzing = false
                }
            }
        }
    }
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
                ? "Pkw"
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

                Section("Fahrzeug") {
                    LabeledContent("Erkannt") {
                        Label(
                            analysis.vehicle.detected ? "Ja" : "Unsicher",
                            systemImage: analysis.vehicle.detected ? "checkmark.circle.fill" : "questionmark.circle"
                        )
                        .foregroundStyle(analysis.vehicle.detected ? .green : .orange)
                    }
                    LabeledContent("Konfidenz", value: analysis.vehicle.confidence, format: .percent.precision(.fractionLength(0)))
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

                Section("Beschreibungsvorschlag") {
                    TextField("Beschreibung", text: $sceneSummary, axis: .vertical)
                        .lineLimit(3...8)
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
