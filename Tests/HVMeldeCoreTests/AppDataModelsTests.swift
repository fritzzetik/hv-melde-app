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
                reportEmail: "meldung@example.com"
            )
        ],
        propertyManagements: [management]
    )

    let decoded = try JSONDecoder().decode(AppDataState.self, from: JSONEncoder().encode(original))

    #expect(decoded == original)
}
