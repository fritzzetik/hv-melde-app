import Foundation
import Testing
@testable import HVMeldeCore

@Test("Unterstützte Länder entsprechen dem MVP")
func supportedCountriesMatchMVP() {
    #expect(SupportedCountry.allCases.map(\.rawValue) == [
        "Deutschland", "Italien", "Österreich", "Liechtenstein", "Schweiz"
    ])
}

@Test("Objekt verwendet ersatzweise die formatierte Anschrift")
func propertyDisplayNameFallsBackToAddress() {
    let property = ManagedProperty(
        name: "  ",
        address: PostalAddress(
            street: "Musterstraße 1",
            postalCode: "1010",
            city: "Wien",
            country: .austria
        )
    )

    #expect(property.displayName == "Musterstraße 1, 1010 Wien, Österreich")
}

@Test("Eine Hausverwaltung kann mehreren Objekten zugeordnet sein")
func managementCanBeSharedByProperties() {
    let management = PropertyManagement(name: "Beispiel Hausverwaltung")
    let first = ManagedProperty(name: "Wohnung 1", propertyManagementID: management.id)
    let second = ManagedProperty(name: "Wohnung 2", propertyManagementID: management.id)

    #expect(first.propertyManagementID == second.propertyManagementID)
}

@Test("Stammdaten bleiben bei lokaler JSON-Speicherung erhalten")
func appDataRoundTrip() throws {
    let management = PropertyManagement(name: "Beispiel Hausverwaltung", email: "hv@example.com")
    let original = AppDataState(
        profile: UserProfile(firstName: "Max", lastName: "Muster", email: "max@example.com"),
        properties: [
            ManagedProperty(
                name: "Wohnung Wien",
                propertyManagementID: management.id,
                reportEmail: "meldung@example.com",
                occupancyRole: .owner
            )
        ],
        propertyManagements: [management],
        reportedCases: [
            StoredReportedCase(
                id: UUID(),
                createdAt: Date(timeIntervalSince1970: 100),
                incidentAt: Date(timeIntervalSince1970: 50),
                propertyID: UUID(),
                propertyName: "Wohnung Wien",
                propertyAddress: PostalAddress(),
                occupancyRole: .owner,
                category: .unauthorizedVehicle,
                garageLocation: "Stellplatz 7",
                licensePlate: "EM 462LG",
                vehicleDescription: "Pkw, Schwarz",
                violation: "Dauerparken",
                notes: "",
                witnesses: "",
                pdfFileName: "Meldung.pdf"
            )
        ]
    )

    let decoded = try JSONDecoder().decode(AppDataState.self, from: JSONEncoder().encode(original))

    #expect(decoded == original)
}

@Test("Bestehende lokale Daten ohne Rolle und Fallliste bleiben lesbar")
func oldAppDataMigratesWithDefaults() throws {
    let oldState = AppDataState(
        properties: [ManagedProperty(name: "Bestandsobjekt", reportEmail: "hv@example.com")]
    )
    let encoded = try JSONEncoder().encode(oldState)
    var json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    json.removeValue(forKey: "reportedCases")
    var properties = try #require(json["properties"] as? [[String: Any]])
    properties[0].removeValue(forKey: "occupancyRole")
    json["properties"] = properties

    let legacyData = try JSONSerialization.data(withJSONObject: json)
    let decoded = try JSONDecoder().decode(AppDataState.self, from: legacyData)

    #expect(decoded.properties.first?.occupancyRole == .tenant)
    #expect(decoded.reportedCases.isEmpty)
}
