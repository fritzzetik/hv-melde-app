import Foundation

public enum IncidentReportField: String, CaseIterable, Sendable {
    case propertyName
    case garageLocation
    case licensePlate
    case violation
}

public struct IncidentReportValidationError: Error, Equatable, Sendable {
    public let missingFields: [IncidentReportField]

    public init(missingFields: [IncidentReportField]) {
        self.missingFields = missingFields
    }
}

public enum IncidentReportValidator {
    public static func validate(_ report: IncidentReport) throws {
        var missingFields: [IncidentReportField] = []

        if report.propertyName.trimmedIsEmpty {
            missingFields.append(.propertyName)
        }
        if report.garageLocation.trimmedIsEmpty {
            missingFields.append(.garageLocation)
        }
        if report.category.expectsVehicle && report.licensePlate.trimmedIsEmpty {
            missingFields.append(.licensePlate)
        }
        if report.violation.trimmedIsEmpty {
            missingFields.append(.violation)
        }

        if !missingFields.isEmpty {
            throw IncidentReportValidationError(missingFields: missingFields)
        }
    }
}

private extension String {
    var trimmedIsEmpty: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
