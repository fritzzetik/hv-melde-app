import Testing
@testable import HVMeldeCore

@Test("Italienisches Kennzeichen wird normalisiert und priorisiert")
func italianPlateIsNormalized() {
    let candidates = LicensePlateParser.candidates(from: [
        OCRTextCandidate(text: "GOLF", confidence: 0.99),
        OCRTextCandidate(text: "EM 462LG", confidence: 0.82),
        OCRTextCandidate(text: "EM-462-LG", confidence: 0.70)
    ])

    #expect(candidates.first?.text == "EM 462LG")
    #expect(candidates.count == 1)
}

@Test("Text ohne Buchstaben und Ziffern wird nicht als Kennzeichen gewertet")
func nonPlateTextIsRejected() {
    let candidates = LicensePlateParser.candidates(from: [
        OCRTextCandidate(text: "GARAGE", confidence: 0.95),
        OCRTextCandidate(text: "123456", confidence: 0.95),
        OCRTextCandidate(text: "TDI", confidence: 0.95)
    ])

    #expect(candidates.isEmpty)
}

@Test("Fahrzeugbegriffe werden mit Konfidenz erkannt")
func vehicleLabelsAreDetected() {
    let detection = VehicleAnalysisInterpreter.detectVehicle(in: [
        ImageClassificationLabel(identifier: "garage", confidence: 0.91),
        ImageClassificationLabel(identifier: "hatchback car", confidence: 0.86)
    ])

    #expect(detection.detected)
    #expect(detection.confidence == 0.86)
}

@Test("Garagenlabel alleine behauptet kein Fahrzeug")
func garageAloneIsNotAVehicle() {
    let detection = VehicleAnalysisInterpreter.detectVehicle(in: [
        ImageClassificationLabel(identifier: "parking garage", confidence: 0.94)
    ])

    #expect(!detection.detected)
}

@Test("Spezifischer Fahrzeugtyp wird vor allgemeinem Pkw-Label verwendet")
func specificVehicleTypeIsPreferred() {
    let suggestion = SceneDetailInterpreter.vehicleType(in: [
        ImageClassificationLabel(identifier: "car, motor vehicle", confidence: 0.92),
        ImageClassificationLabel(identifier: "hatchback", confidence: 0.71)
    ])

    #expect(suggestion?.name == "Kompaktwagen / Schrägheck")
    #expect(suggestion?.confidence == 0.71)
}

@Test("Matratze wird als relevantes Nebenobjekt vorgeschlagen")
func mattressIsRelevantSceneObject() {
    let suggestions = SceneDetailInterpreter.relevantObjects(in: [
        ImageClassificationLabel(identifier: "parking garage", confidence: 0.94),
        ImageClassificationLabel(identifier: "mattress, bedding", confidence: 0.18)
    ])

    #expect(suggestions.first?.name == "Matratze")
    #expect(suggestions.first?.confidence == 0.18)
}

@Test("Niedrige generische Möbel-Konfidenz wird nicht vorgeschlagen")
func weakFurnitureLabelIsRejected() {
    let suggestions = SceneDetailInterpreter.relevantObjects(in: [
        ImageClassificationLabel(identifier: "furniture", confidence: 0.02)
    ])

    #expect(suggestions.isEmpty)
}

@Test("Unsicheres SUV-Label wird nicht als Fahrzeugtyp vorbefüllt")
func weakSUVFallsBackToGeneralVehicleType() {
    let suggestion = SceneDetailInterpreter.vehicleType(in: [
        ImageClassificationLabel(identifier: "car, motor vehicle", confidence: 0.75),
        ImageClassificationLabel(identifier: "sport utility vehicle, SUV", confidence: 0.24)
    ])

    #expect(suggestion?.name == "Pkw")
    #expect(suggestion?.confidence == 0.75)
}

@Test("Normale Fahrzeugreifen werden nicht als Nebenobjekt gemeldet")
func tiresAreSuppressedForVehicleReports() {
    let suggestions = SceneDetailInterpreter.relevantObjects(
        in: [ImageClassificationLabel(identifier: "tire, tyre", confidence: 0.40)],
        category: .unauthorizedVehicle
    )

    #expect(suggestions.isEmpty)
}

@Test("Reifen bleiben bei einer Sperrmüllmeldung ein möglicher Treffer")
func tiresRemainRelevantForWasteReports() {
    let suggestions = SceneDetailInterpreter.relevantObjects(
        in: [ImageClassificationLabel(identifier: "tire, tyre", confidence: 0.40)],
        category: .bulkyWaste
    )

    #expect(suggestions.first?.name == "Reifen")
}
