import CryptoKit
import Foundation
import HVMeldeCore
import Vision

struct LocalImageAnalysis: Identifiable, Sendable {
    let id = UUID()
    let category: ReportCategory
    let vehicle: VehicleDetection
    let vehicleType: VehicleTypeSuggestion?
    let vehicleColor: VehicleColorSuggestion?
    let relevantObjects: [SceneObjectSuggestion]
    let plateCandidates: [LicensePlateCandidate]
    let classifications: [ImageClassificationLabel]
    let recognizedTexts: [OCRTextCandidate]
    let imageSHA256: String

    var suggestedVehicleDescription: String {
        guard vehicle.detected else { return "" }
        var details = ["Pkw"]
        if let vehicleType, vehicleType.name != "Pkw" {
            details.append("Typ: \(vehicleType.name)")
        }
        if let vehicleColor {
            details.append("Farbe: \(vehicleColor.name)")
        }
        return details.joined(separator: ", ")
    }

    var sceneSummary: String {
        var sentences: [String] = []

        if vehicle.detected {
            sentences.append("Auf dem Foto wurde ein Fahrzeug erkannt.")
        } else if category.expectsVehicle {
            sentences.append("Auf dem Foto wurde kein Fahrzeug mit ausreichender Sicherheit erkannt.")
        }

        if let vehicleType {
            sentences.append("Als möglicher Fahrzeugtyp wurde \(vehicleType.name) erkannt.")
        }
        if let vehicleColor {
            sentences.append("Die Fahrzeugfarbe wird heuristisch als \(vehicleColor.name) geschätzt.")
        }

        if let plate = plateCandidates.first {
            sentences.append("Als mögliches Kennzeichen wurde \(plate.text) gelesen.")
        } else if category.expectsVehicle {
            sentences.append("Es wurde kein ausreichend plausibles Kennzeichen gelesen.")
        }

        if !relevantObjects.isEmpty {
            let names = relevantObjects.map(\.name).joined(separator: ", ")
            sentences.append("Als mögliche weitere Objekte wurden erkannt: \(names).")
        }

        sentences.append("Gewählte Meldekategorie: \(category.rawValue).")
        return sentences.joined(separator: " ")
    }
}

enum LocalImageAnalyzer {
    static func analyze(imageData: Data, category: ReportCategory) async throws -> LocalImageAnalysis {
        async let classifications = classify(imageData: imageData)
        async let recognizedTexts = recognizeText(imageData: imageData)
        async let vehicleColor = VehicleColorAnalyzer.analyze(imageData: imageData)

        let (classificationResults, textResults, colorResult) = try await (
            classifications,
            recognizedTexts,
            vehicleColor
        )
        let vehicle = VehicleAnalysisInterpreter.detectVehicle(in: classificationResults)
        let vehicleType = SceneDetailInterpreter.vehicleType(in: classificationResults)
        let relevantObjects = SceneDetailInterpreter.relevantObjects(
            in: classificationResults,
            category: category
        )
        let plates = LicensePlateParser.candidates(from: textResults)
        let digest = SHA256.hash(data: imageData).map { String(format: "%02x", $0) }.joined()

        return LocalImageAnalysis(
            category: category,
            vehicle: vehicle,
            vehicleType: vehicleType,
            vehicleColor: vehicle.detected ? colorResult : nil,
            relevantObjects: relevantObjects,
            plateCandidates: plates,
            classifications: classificationResults,
            recognizedTexts: textResults,
            imageSHA256: digest
        )
    }

    private static func classify(imageData: Data) async throws -> [ImageClassificationLabel] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(data: imageData)
            try handler.perform([request])

            return (request.results ?? [])
                .prefix(120)
                .map { ImageClassificationLabel(identifier: $0.identifier, confidence: $0.confidence) }
        }.value
    }

    private static func recognizeText(imageData: Data) async throws -> [OCRTextCandidate] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let supportedLanguages = try VNRecognizeTextRequest.supportedRecognitionLanguages(
                for: .accurate,
                revision: request.revision
            )
            request.recognitionLanguages = ["de-DE", "en-US", "it-IT"].filter(supportedLanguages.contains)

            let handler = VNImageRequestHandler(data: imageData)
            try handler.perform([request])

            return (request.results ?? []).compactMap { observation in
                observation.topCandidates(1).first.map {
                    OCRTextCandidate(text: $0.string, confidence: $0.confidence)
                }
            }
        }.value
    }
}
