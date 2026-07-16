import Foundation
import HVMeldeCore

struct IncidentDraft: Codable, Equatable, Sendable {
    var reportID: UUID
    var reportCreatedAt: Date
    var selectedPropertyID: UUID?
    var category: ReportCategory
    var incidentAt: Date
    var garageLocation: String
    var isCommonArea: Bool
    var licensePlate: String
    var vehicleDescription: String
    var violation: String
    var notes: String
    var witnesses: String
    var evidencePhotoCount: Int
    var requestsManagementResponse: Bool?
    var allowsNameDisclosure: Bool?

    var wantsManagementResponse: Bool { requestsManagementResponse ?? true }
    var permitsNameDisclosure: Bool { allowsNameDisclosure ?? false }

    var hasMeaningfulContent: Bool {
        !garageLocation.trimmed.isEmpty
            || isCommonArea
            || !licensePlate.trimmed.isEmpty
            || !vehicleDescription.trimmed.isEmpty
            || violation.trimmed != category.defaultViolation.trimmed
            || !notes.trimmed.isEmpty
            || !witnesses.trimmed.isEmpty
            || evidencePhotoCount > 0
            || !wantsManagementResponse
            || permitsNameDisclosure
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
