import Foundation

public struct IncidentReport: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public var incidentAt: Date
    public var propertyName: String
    public var garageLocation: String
    public var licensePlate: String
    public var vehicleDescription: String
    public var violation: String
    public var notes: String
    public var witnesses: String
    public var isCommonArea: Bool

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        incidentAt: Date,
        propertyName: String,
        garageLocation: String,
        licensePlate: String,
        vehicleDescription: String = "",
        violation: String,
        notes: String = "",
        witnesses: String = "",
        isCommonArea: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.incidentAt = incidentAt
        self.propertyName = propertyName
        self.garageLocation = garageLocation
        self.licensePlate = licensePlate
        self.vehicleDescription = vehicleDescription
        self.violation = violation
        self.notes = notes
        self.witnesses = witnesses
        self.isCommonArea = isCommonArea
    }
}
