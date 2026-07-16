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

@Test("Strukturierte Anschrift enthält Hausnummer und Top")
func structuredAddressIsFormatted() {
    let address = PostalAddress(
        street: "J.W.-Goethestraße",
        houseNumber: "114",
        unit: "14",
        postalCode: "39012",
        city: "Meran",
        country: .italy
    )

    #expect(address.formatted == "J.W.-Goethestraße 114, Top 14, 39012 Meran, Italien")
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
                address: PostalAddress(street: "Musterstraße", houseNumber: "1", unit: "7"),
                propertyManagementID: management.id,
                reportEmail: "meldung@example.com",
                occupancyRole: .owner,
                officialName: "Wohnanlage Musterhof",
                propertyType: .apartment
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
                pdfFileName: "Meldung.pdf",
                isCommonArea: true,
                officialPropertyName: "Wohnanlage Musterhof",
                propertyType: .apartment,
                requestsManagementResponse: false,
                allowsNameDisclosure: true
            )
        ],
        preferences: AppPreferences(
            enhancedLocalAnalysisEnabled: true,
            technicalAttachmentMode: .json
        )
    )

    let decoded = try JSONDecoder().decode(AppDataState.self, from: JSONEncoder().encode(original))

    #expect(decoded == original)
}

@Test("Bestehender Fall ohne Flächenangabe gilt als objektbezogen")
func oldCaseWithoutAreaScopeDefaultsToOwnObject() throws {
    let storedCase = StoredReportedCase(
        id: UUID(),
        createdAt: Date(timeIntervalSince1970: 100),
        incidentAt: Date(timeIntervalSince1970: 50),
        propertyID: UUID(),
        propertyName: "Bestandsobjekt",
        propertyAddress: PostalAddress(),
        occupancyRole: .tenant,
        category: .damage,
        garageLocation: "Stiegenhaus",
        licensePlate: "",
        vehicleDescription: "",
        violation: "Beschädigung",
        notes: "",
        witnesses: "",
        pdfFileName: "Meldung.pdf"
    )
    let encoded = try JSONEncoder().encode(storedCase)
    var json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    json.removeValue(forKey: "isCommonArea")
    json.removeValue(forKey: "requestsManagementResponse")
    json.removeValue(forKey: "allowsNameDisclosure")

    let legacyData = try JSONSerialization.data(withJSONObject: json)
    let decoded = try JSONDecoder().decode(StoredReportedCase.self, from: legacyData)

    #expect(!decoded.concernsCommonArea)
    #expect(decoded.recipientPropertyName == "Bestandsobjekt")
    #expect(decoded.resolvedPropertyType == .apartment)
    #expect(decoded.technicalJSONFileName == nil)
    #expect(decoded.cloudFiles == nil)
    #expect(decoded.wantsManagementResponse)
    #expect(!decoded.permitsNameDisclosure)
}

@Test("Bestehende lokale Daten ohne Rolle und Fallliste bleiben lesbar")
func oldAppDataMigratesWithDefaults() throws {
    let oldState = AppDataState(
        properties: [ManagedProperty(name: "Bestandsobjekt", reportEmail: "hv@example.com")]
    )
    let encoded = try JSONEncoder().encode(oldState)
    var json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    json.removeValue(forKey: "reportedCases")
    json.removeValue(forKey: "reportCategories")
    json.removeValue(forKey: "preferences")
    var properties = try #require(json["properties"] as? [[String: Any]])
    properties[0].removeValue(forKey: "occupancyRole")
    properties[0].removeValue(forKey: "officialName")
    properties[0].removeValue(forKey: "propertyType")
    if var address = properties[0]["address"] as? [String: Any] {
        address.removeValue(forKey: "houseNumber")
        address.removeValue(forKey: "unit")
        properties[0]["address"] = address
    }
    json["properties"] = properties

    let legacyData = try JSONSerialization.data(withJSONObject: json)
    let decoded = try JSONDecoder().decode(AppDataState.self, from: legacyData)

    #expect(decoded.properties.first?.occupancyRole == .tenant)
    #expect(decoded.properties.first?.officialName == "")
    #expect(decoded.properties.first?.propertyType == .apartment)
    #expect(decoded.properties.first?.address.houseNumber == "")
    #expect(decoded.properties.first?.address.unit == "")
    #expect(decoded.reportedCases.isEmpty)
    #expect(decoded.reportCategories == ReportCategory.defaultCategories)
    #expect(!decoded.preferences.enhancedLocalAnalysisEnabled)
    #expect(decoded.preferences.technicalAttachmentMode == .none)
    #expect(decoded.deletedCases.isEmpty)
    #expect(decoded.deletedCloudFileRecordNames.isEmpty)
}

@Test("Alte als Text gespeicherte Meldekategorie bleibt lesbar")
func legacyReportCategoryMigrates() throws {
    let legacyData = try #require("\"Beschädigung\"".data(using: .utf8))

    let decoded = try JSONDecoder().decode(ReportCategory.self, from: legacyData)

    #expect(decoded == .damage)
    #expect(!decoded.expectsVehicle)
}

@Test("Eigene Meldekategorie behält Eingaberegeln")
func customReportCategoryRoundTrip() throws {
    let original = ReportCategory(
        name: "Falsch abgestelltes Fahrrad",
        defaultViolation: "Fahrrad blockiert den Fluchtweg",
        expectsVehicle: false,
        sortOrder: 20,
        updatedAt: Date(timeIntervalSince1970: 500)
    )

    let decoded = try JSONDecoder().decode(ReportCategory.self, from: JSONEncoder().encode(original))

    #expect(decoded == original)
    #expect(!decoded.isBuiltIn)
}

@Test("Alte Meldung erhält datenschutzfreundliche Bearbeitungswünsche")
func oldIncidentReportDefaultsResponseAndDisclosure() throws {
    let report = IncidentReport(
        incidentAt: Date(timeIntervalSince1970: 100),
        propertyName: "Wohnanlage",
        garageLocation: "Eingang",
        licensePlate: "",
        violation: "Beleuchtung ausgefallen",
        category: .lighting
    )
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])
    json.removeValue(forKey: "requestsManagementResponse")
    json.removeValue(forKey: "allowsNameDisclosure")

    let decoded = try JSONDecoder().decode(
        IncidentReport.self,
        from: JSONSerialization.data(withJSONObject: json)
    )

    #expect(decoded.wantsManagementResponse)
    #expect(!decoded.permitsNameDisclosure)
}

@Test("Cloud-Dateiliste bleibt im verschlüsselten App-Snapshot erhalten")
func cloudFileManifestRoundTrip() throws {
    let caseID = UUID()
    let fileID = UUID()
    let reference = CloudCaseFileReference(
        id: fileID,
        caseID: caseID,
        kind: .photo,
        fileName: "original-\(fileID.uuidString).jpg",
        sha256: "abc123",
        createdAt: Date(timeIntervalSince1970: 200),
        metadata: Data("{}".utf8)
    )
    let storedCase = StoredReportedCase(
        id: caseID,
        createdAt: Date(timeIntervalSince1970: 100),
        incidentAt: Date(timeIntervalSince1970: 50),
        propertyID: UUID(),
        propertyName: "Bestandsobjekt",
        propertyAddress: PostalAddress(),
        occupancyRole: .tenant,
        category: .damage,
        garageLocation: "Stiegenhaus",
        licensePlate: "",
        vehicleDescription: "",
        violation: "Beschädigung",
        notes: "",
        witnesses: "",
        pdfFileName: "Meldung.pdf",
        cloudFiles: [reference]
    )
    let original = AppDataState(
        reportedCases: [storedCase],
        deletedCases: [DeletedCaseTombstone(id: UUID(), deletedAt: Date(timeIntervalSince1970: 300))],
        deletedCloudFileRecordNames: ["alter-record"]
    )

    let decoded = try JSONDecoder().decode(AppDataState.self, from: JSONEncoder().encode(original))

    #expect(decoded == original)
    #expect(decoded.reportedCases.first?.cloudFiles?.first?.recordName == reference.recordName)
}
