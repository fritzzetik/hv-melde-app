import Foundation
import Testing
@testable import HVMeldeCore

@Test("Eine vollständige Meldung ist gültig")
func completeReportIsValid() throws {
    let report = IncidentReport(
        incidentAt: Date(timeIntervalSince1970: 1_700_000_000),
        propertyName: "Musterstraße 1",
        garageLocation: "Ebene 2, Stellplatz 17",
        licensePlate: "W-12345X",
        violation: "Dauerparken"
    )

    try IncidentReportValidator.validate(report)
}

@Test("Leerzeichen gelten bei Pflichtfeldern als leer")
func whitespaceOnlyFieldsAreRejected() {
    let report = IncidentReport(
        incidentAt: Date(timeIntervalSince1970: 1_700_000_000),
        propertyName: "  ",
        garageLocation: "\n",
        licensePlate: "",
        violation: "\t"
    )

    #expect(throws: IncidentReportValidationError(
        missingFields: [.propertyName, .garageLocation, .licensePlate, .violation]
    )) {
        try IncidentReportValidator.validate(report)
    }
}

@Test("Nicht fahrzeugbezogene Meldung benötigt kein Kennzeichen")
func nonVehicleReportDoesNotRequirePlate() throws {
    let report = IncidentReport(
        incidentAt: Date(timeIntervalSince1970: 1_700_000_000),
        propertyName: "Musterobjekt",
        garageLocation: "Stiegenhaus",
        licensePlate: "",
        violation: "Beschädigte Beleuchtung",
        category: .damage
    )

    try IncidentReportValidator.validate(report)
}
