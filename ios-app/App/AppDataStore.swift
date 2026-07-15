import Combine
import Foundation
import HVMeldeCore

@MainActor
final class AppDataStore: ObservableObject {
    @Published private(set) var state: AppDataState
    @Published private(set) var lastError: String?

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        let resolvedURL = fileURL ?? Self.defaultFileURL
        self.fileURL = resolvedURL
        self.state = Self.load(from: resolvedURL)
    }

    func saveProfile(_ profile: UserProfile) {
        state.profile = profile
        persist()
    }

    func upsert(_ property: ManagedProperty) {
        if let index = state.properties.firstIndex(where: { $0.id == property.id }) {
            state.properties[index] = property
        } else {
            state.properties.append(property)
        }
        state.properties.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        persist()
    }

    func deleteProperties(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            state.properties.remove(at: offset)
        }
        persist()
    }

    func upsert(_ management: PropertyManagement) {
        if let index = state.propertyManagements.firstIndex(where: { $0.id == management.id }) {
            state.propertyManagements[index] = management
        } else {
            state.propertyManagements.append(management)
        }
        state.propertyManagements.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persist()
    }

    func deletePropertyManagements(at offsets: IndexSet) {
        let deletedIDs = Set(offsets.map { state.propertyManagements[$0].id })
        for offset in offsets.sorted(by: >) {
            state.propertyManagements.remove(at: offset)
        }
        for index in state.properties.indices where state.properties[index].propertyManagementID.map(deletedIDs.contains) == true {
            state.properties[index].propertyManagementID = nil
        }
        persist()
    }

    func management(for property: ManagedProperty) -> PropertyManagement? {
        guard let id = property.propertyManagementID else { return nil }
        return state.propertyManagements.first { $0.id == id }
    }

    func saveReportedCase(
        report: IncidentReport,
        category: ReportCategory,
        property: ManagedProperty,
        generatedPDFURL: URL,
        evidenceSHA256: String?
    ) throws -> URL {
        do {
            let caseDirectory = casesDirectory.appendingPathComponent(report.id.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: caseDirectory, withIntermediateDirectories: true)
            let pdfFileName = "Meldung-\(report.id.uuidString).pdf"
            let permanentPDFURL = caseDirectory.appendingPathComponent(pdfFileName)
            let pdfData = try Data(contentsOf: generatedPDFURL)
            try pdfData.write(to: permanentPDFURL, options: [.atomic, .completeFileProtection])

            let existing = state.reportedCases.first { $0.id == report.id }
            let storedCase = StoredReportedCase(
                id: report.id,
                createdAt: report.createdAt,
                updatedAt: Date(),
                incidentAt: report.incidentAt,
                propertyID: property.id,
                propertyName: property.displayName,
                propertyAddress: property.address,
                occupancyRole: property.occupancyRole,
                category: category,
                garageLocation: report.garageLocation,
                licensePlate: report.licensePlate,
                vehicleDescription: report.vehicleDescription,
                violation: report.violation,
                notes: report.notes,
                witnesses: report.witnesses,
                status: existing?.status ?? .open,
                completedAt: existing?.completedAt,
                pdfFileName: pdfFileName,
                evidenceSHA256: evidenceSHA256,
                isCommonArea: report.isCommonArea
            )
            if let index = state.reportedCases.firstIndex(where: { $0.id == report.id }) {
                state.reportedCases[index] = storedCase
            } else {
                state.reportedCases.append(storedCase)
            }
            try persistState()
            lastError = nil
            return permanentPDFURL
        } catch {
            lastError = "Der Fall konnte nicht lokal gespeichert werden: \(error.localizedDescription)"
            throw error
        }
    }

    func setCaseStatus(_ status: ReportedCaseStatus, for id: UUID) {
        guard let index = state.reportedCases.firstIndex(where: { $0.id == id }) else { return }
        state.reportedCases[index].status = status
        state.reportedCases[index].completedAt = status == .completed ? Date() : nil
        state.reportedCases[index].updatedAt = Date()
        persist()
    }

    func pdfURL(for reportedCase: StoredReportedCase) -> URL? {
        let url = casesDirectory
            .appendingPathComponent(reportedCase.id.uuidString, isDirectory: true)
            .appendingPathComponent(reportedCase.pdfFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func clearError() {
        lastError = nil
    }

    private func persist() {
        do {
            try persistState()
            lastError = nil
        } catch {
            lastError = "Die Einstellungen konnten nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    private func persistState() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    private var casesDirectory: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("Cases", isDirectory: true)
    }

    private static func load(from url: URL) -> AppDataState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(AppDataState.self, from: data) else {
            return AppDataState()
        }
        return state
    }

    private static var defaultFileURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("HVMeldeApp", isDirectory: true)
            .appendingPathComponent("app-data.json")
    }
}
