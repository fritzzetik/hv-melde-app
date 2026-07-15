import Foundation

public enum SupportedCountry: String, CaseIterable, Codable, Identifiable, Sendable {
    case germany = "Deutschland"
    case italy = "Italien"
    case austria = "Österreich"
    case liechtenstein = "Liechtenstein"
    case switzerland = "Schweiz"

    public var id: String { rawValue }
}

public struct PostalAddress: Codable, Equatable, Sendable {
    public var street: String
    public var houseNumber: String
    public var unit: String
    public var postalCode: String
    public var city: String
    public var country: SupportedCountry

    public init(
        street: String = "",
        houseNumber: String = "",
        unit: String = "",
        postalCode: String = "",
        city: String = "",
        country: SupportedCountry = .austria
    ) {
        self.street = street
        self.houseNumber = houseNumber
        self.unit = unit
        self.postalCode = postalCode
        self.city = city
        self.country = country
    }

    public var formatted: String {
        let streetLine = [street.trimmed, houseNumber.trimmed]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let trimmedUnit = unit.trimmed
        let unitLine = trimmedUnit.isEmpty
            ? ""
            : (trimmedUnit.lowercased().hasPrefix("top") ? trimmedUnit : "Top \(trimmedUnit)")
        return [streetLine, unitLine, [postalCode.trimmed, city.trimmed].filter { !$0.isEmpty }.joined(separator: " "), country.rawValue]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private enum CodingKeys: String, CodingKey {
        case street, houseNumber, unit, postalCode, city, country
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        street = try container.decodeIfPresent(String.self, forKey: .street) ?? ""
        houseNumber = try container.decodeIfPresent(String.self, forKey: .houseNumber) ?? ""
        unit = try container.decodeIfPresent(String.self, forKey: .unit) ?? ""
        postalCode = try container.decodeIfPresent(String.self, forKey: .postalCode) ?? ""
        city = try container.decodeIfPresent(String.self, forKey: .city) ?? ""
        country = try container.decodeIfPresent(SupportedCountry.self, forKey: .country) ?? .austria
    }
}

public struct UserProfile: Codable, Equatable, Sendable {
    public var firstName: String
    public var lastName: String
    public var address: PostalAddress
    public var phone: String
    public var email: String

    public init(
        firstName: String = "",
        lastName: String = "",
        address: PostalAddress = PostalAddress(),
        phone: String = "",
        email: String = ""
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.address = address
        self.phone = phone
        self.email = email
    }

    public var fullName: String {
        [firstName.trimmed, lastName.trimmed].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

public struct PropertyManagement: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var address: PostalAddress
    public var phone: String
    public var email: String

    public init(
        id: UUID = UUID(),
        name: String = "",
        address: PostalAddress = PostalAddress(),
        phone: String = "",
        email: String = ""
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.phone = phone
        self.email = email
    }
}

public enum OccupancyRole: String, CaseIterable, Codable, Identifiable, Sendable {
    case tenant = "Mieter"
    case owner = "Eigentümer"

    public var id: String { rawValue }
}

public enum PropertyType: String, CaseIterable, Codable, Identifiable, Sendable {
    case apartment = "Wohnung"
    case garage = "Garage"
    case commercialSpace = "Gewerbliche Fläche"
    case basement = "Keller"
    case storage = "Lager"
    case other = "Sonstiges"

    public var id: String { rawValue }
}

public struct ManagedProperty: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var address: PostalAddress
    public var propertyManagementID: UUID?
    public var reportEmail: String
    public var occupancyRole: OccupancyRole
    public var officialName: String
    public var propertyType: PropertyType

    public init(
        id: UUID = UUID(),
        name: String = "",
        address: PostalAddress = PostalAddress(),
        propertyManagementID: UUID? = nil,
        reportEmail: String = "",
        occupancyRole: OccupancyRole = .tenant,
        officialName: String = "",
        propertyType: PropertyType = .apartment
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.propertyManagementID = propertyManagementID
        self.reportEmail = reportEmail
        self.occupancyRole = occupancyRole
        self.officialName = officialName
        self.propertyType = propertyType
    }

    public var displayName: String {
        let trimmedName = name.trimmed
        return trimmedName.isEmpty ? address.formatted : trimmedName
    }

    public var officialDisplayName: String {
        let value = officialName.trimmed
        return value.isEmpty ? displayName : value
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, address, propertyManagementID, reportEmail, occupancyRole, officialName, propertyType
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(PostalAddress.self, forKey: .address)
        propertyManagementID = try container.decodeIfPresent(UUID.self, forKey: .propertyManagementID)
        reportEmail = try container.decode(String.self, forKey: .reportEmail)
        occupancyRole = try container.decodeIfPresent(OccupancyRole.self, forKey: .occupancyRole) ?? .tenant
        officialName = try container.decodeIfPresent(String.self, forKey: .officialName) ?? ""
        propertyType = try container.decodeIfPresent(PropertyType.self, forKey: .propertyType) ?? .apartment
    }
}

public enum ReportedCaseStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case open = "Offen"
    case completed = "Erledigt"

    public var id: String { rawValue }
}

public struct StoredReportedCase: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public var updatedAt: Date
    public let incidentAt: Date
    public let propertyID: UUID
    public let propertyName: String
    public let propertyAddress: PostalAddress
    public let occupancyRole: OccupancyRole
    public let category: ReportCategory
    public let garageLocation: String
    public let licensePlate: String
    public let vehicleDescription: String
    public let violation: String
    public let notes: String
    public let witnesses: String
    public var status: ReportedCaseStatus
    public var completedAt: Date?
    public let pdfFileName: String
    public let evidenceSHA256: String?
    public let isCommonArea: Bool?
    public let officialPropertyName: String?
    public let propertyType: PropertyType?

    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date = Date(),
        incidentAt: Date,
        propertyID: UUID,
        propertyName: String,
        propertyAddress: PostalAddress,
        occupancyRole: OccupancyRole,
        category: ReportCategory,
        garageLocation: String,
        licensePlate: String,
        vehicleDescription: String,
        violation: String,
        notes: String,
        witnesses: String,
        status: ReportedCaseStatus = .open,
        completedAt: Date? = nil,
        pdfFileName: String,
        evidenceSHA256: String? = nil,
        isCommonArea: Bool = false,
        officialPropertyName: String? = nil,
        propertyType: PropertyType? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.incidentAt = incidentAt
        self.propertyID = propertyID
        self.propertyName = propertyName
        self.propertyAddress = propertyAddress
        self.occupancyRole = occupancyRole
        self.category = category
        self.garageLocation = garageLocation
        self.licensePlate = licensePlate
        self.vehicleDescription = vehicleDescription
        self.violation = violation
        self.notes = notes
        self.witnesses = witnesses
        self.status = status
        self.completedAt = completedAt
        self.pdfFileName = pdfFileName
        self.evidenceSHA256 = evidenceSHA256
        self.isCommonArea = isCommonArea
        self.officialPropertyName = officialPropertyName
        self.propertyType = propertyType
    }

    public var concernsCommonArea: Bool { isCommonArea ?? false }

    public var recipientPropertyName: String {
        let value = officialPropertyName?.trimmed ?? ""
        return value.isEmpty ? propertyName : value
    }

    public var resolvedPropertyType: PropertyType { propertyType ?? .apartment }
}

public struct AppDataState: Codable, Equatable, Sendable {
    public var profile: UserProfile
    public var properties: [ManagedProperty]
    public var propertyManagements: [PropertyManagement]
    public var reportedCases: [StoredReportedCase]

    public init(
        profile: UserProfile = UserProfile(),
        properties: [ManagedProperty] = [],
        propertyManagements: [PropertyManagement] = [],
        reportedCases: [StoredReportedCase] = []
    ) {
        self.profile = profile
        self.properties = properties
        self.propertyManagements = propertyManagements
        self.reportedCases = reportedCases
    }

    private enum CodingKeys: String, CodingKey {
        case profile, properties, propertyManagements, reportedCases
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profile = try container.decodeIfPresent(UserProfile.self, forKey: .profile) ?? UserProfile()
        properties = try container.decodeIfPresent([ManagedProperty].self, forKey: .properties) ?? []
        propertyManagements = try container.decodeIfPresent([PropertyManagement].self, forKey: .propertyManagements) ?? []
        reportedCases = try container.decodeIfPresent([StoredReportedCase].self, forKey: .reportedCases) ?? []
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
