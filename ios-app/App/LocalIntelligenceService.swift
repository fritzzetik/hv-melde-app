import Foundation
import HVMeldeCore

#if canImport(FoundationModels)
import FoundationModels
#endif

enum LocalIntelligenceAvailability: Equatable, Sendable {
    case available
    case requiresNewerOS
    case appleIntelligenceUnavailable

    var settingsDescription: String {
        switch self {
        case .available:
            "Auf diesem Gerät verfügbar"
        case .requiresNewerOS:
            "Erfordert iOS 26 oder neuer"
        case .appleIntelligenceUnavailable:
            "Apple Intelligence ist auf diesem Gerät derzeit nicht verfügbar"
        }
    }
}

enum LocalIntelligenceOutcome: Equatable, Sendable {
    case disabled
    case applied
    case unavailable
    case failed

    var description: String? {
        switch self {
        case .disabled:
            nil
        case .applied:
            "Der Beschreibungsvorschlag wurde zusätzlich mit Apple Intelligence lokal formuliert."
        case .unavailable:
            "Apple Intelligence war nicht verfügbar; die lokale Vision-Erkennung wurde verwendet."
        case .failed:
            "Die erweiterte lokale Formulierung war nicht möglich; die Vision-Erkennung wurde verwendet."
        }
    }
}

enum LocalIntelligenceService {
    static var availability: LocalIntelligenceAvailability {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else {
                return .appleIntelligenceUnavailable
            }
            return .available
        }
#endif
        return .requiresNewerOS
    }

    static func refineSceneSummary(
        category: ReportCategory,
        vehicle: VehicleDetection,
        vehicleType: VehicleTypeSuggestion?,
        vehicleColor: VehicleColorSuggestion?,
        relevantObjects: [SceneObjectSuggestion],
        plateCandidates: [LicensePlateCandidate],
        classifications: [ImageClassificationLabel],
        recognizedTexts: [OCRTextCandidate]
    ) async throws -> String? {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }

            let observations = promptObservations(
                category: category,
                vehicle: vehicle,
                vehicleType: vehicleType,
                vehicleColor: vehicleColor,
                relevantObjects: relevantObjects,
                plateCandidates: plateCandidates,
                classifications: classifications,
                recognizedTexts: recognizedTexts
            )
            let session = LanguageModelSession(instructions: """
                Du formulierst sachliche, kurze Beschreibungsvorschläge für Meldungen an eine Hausverwaltung.
                Verwende ausschließlich die bereitgestellten maschinellen Beobachtungen. Erfinde keine Details.
                Unsichere Beobachtungen müssen als möglicherweise oder vermutlich gekennzeichnet werden.
                Triff keine rechtliche Bewertung und behaupte nicht, dass ein Verstoß bewiesen ist.
                Antworte auf Deutsch als Fließtext mit höchstens vier kurzen Sätzen, ohne Überschrift oder Aufzählung.
                """)
            let response = try await session.respond(to: observations)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
#endif
        return nil
    }

    private static func promptObservations(
        category: ReportCategory,
        vehicle: VehicleDetection,
        vehicleType: VehicleTypeSuggestion?,
        vehicleColor: VehicleColorSuggestion?,
        relevantObjects: [SceneObjectSuggestion],
        plateCandidates: [LicensePlateCandidate],
        classifications: [ImageClassificationLabel],
        recognizedTexts: [OCRTextCandidate]
    ) -> String {
        let objects = relevantObjects.map { "\($0.name) (\(percent($0.confidence)))" }.joined(separator: ", ")
        let labels = classifications.prefix(15).map {
            "\($0.identifier) (\(percent($0.confidence)))"
        }.joined(separator: ", ")
        let texts = recognizedTexts.prefix(12).map { $0.text }.joined(separator: " | ")

        return """
            Erstelle den Beschreibungsvorschlag zu der vorgewählten Kategorie „\(category.rawValue)“.
            Fahrzeugerkennung: \(vehicle.detected ? "erkannt" : "nicht sicher erkannt") (\(percent(vehicle.confidence))).
            Vorgeschlagener Fahrzeugtyp: \(vehicleType.map { "\($0.name) (\(percent($0.confidence)))" } ?? "keiner").
            Heuristisch geschätzte Farbe: \(vehicleColor.map { "\($0.name) (\(percent($0.confidence)))" } ?? "keine").
            Plausibles Kennzeichen: \(plateCandidates.first?.text ?? "keines").
            Relevante Nebenobjekte: \(objects.isEmpty ? "keine" : objects).
            Allgemeine Bildklassifikationen: \(labels.isEmpty ? "keine" : labels).
            Erkannter Bildtext: \(texts.isEmpty ? "keiner" : texts).
            """
    }

    private static func percent(_ confidence: Float) -> String {
        "\(Int((confidence * 100).rounded())) %"
    }
}
