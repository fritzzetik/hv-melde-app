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
    public var postalCode: String
    public var city: String
    public var country: SupportedCountry

    public init(
        street: String = "",
        postalCode: String = "",
        city: String = "",
        country: SupportedCountry = .austria
    ) {
        self.street = street
        self.postalCode = postalCode
        self.city = city
        self.country = country
    }

    public var formatted: String {
        [street.trimmed, [postalCode.trimmed, city.trimmed].filter { !$0.isEmpty }.joined(separator: " "), country.rawValue]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
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

public struct ManagedProperty: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var address: PostalAddress
    public var propertyManagementID: UUID?
    public var reportEmail: String

    public init(
        id: UUID = UUID(),
        name: String = "",
        address: PostalAddress = PostalAddress(),
        propertyManagementID: UUID? = nil,
        reportEmail: String = ""
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.propertyManagementID = propertyManagementID
        self.reportEmail = reportEmail
    }

    public var displayName: String {
        let trimmedName = name.trimmed
        return trimmedName.isEmpty ? address.formatted : trimmedName
    }
}

public struct AppDataState: Codable, Equatable, Sendable {
    public var profile: UserProfile
    public var properties: [ManagedProperty]
    public var propertyManagements: [PropertyManagement]

    public init(
        profile: UserProfile = UserProfile(),
        properties: [ManagedProperty] = [],
        propertyManagements: [PropertyManagement] = []
    ) {
        self.profile = profile
        self.properties = properties
        self.propertyManagements = propertyManagements
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

