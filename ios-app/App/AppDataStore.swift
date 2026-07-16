import Combine
import Foundation
import HVMeldeCore
import Security

@MainActor
final class AppDataStore: ObservableObject {
    @Published private(set) var state: AppDataState
    @Published private(set) var lastError: String?
    @Published private(set) var incidentDraft: IncidentDraft?
    @Published private(set) var iCloudSyncEnabled: Bool
    @Published private(set) var iCloudSyncStatus: ICloudSyncStatus

    private let fileURL: URL
    // CloudKit must not be initialized during app launch. This also keeps the app
    // usable when iCloud is disabled or the distribution profile is temporarily stale.
    private lazy var cloudSyncService = CloudKitSyncService()
    private var cloudSyncTask: Task<Void, Never>?
    private var stateModifiedAt: Date
    private var lastCloudSyncAt: Date?
    private var isCloudSyncInProgress = false

    private static let cloudSyncEnabledKey = "cloudSyncEnabled"
    private static let lastCloudSyncAtKey = "lastCloudSyncAt"

    init(fileURL: URL? = nil) {
        let resolvedURL = fileURL ?? Self.defaultFileURL
        self.fileURL = resolvedURL
        self.state = Self.load(from: resolvedURL)
        self.incidentDraft = Self.loadDraft(from: Self.draftURL(for: resolvedURL))
        let syncEnabled = UserDefaults.standard.bool(forKey: Self.cloudSyncEnabledKey)
        self.iCloudSyncEnabled = syncEnabled
        self.lastCloudSyncAt = UserDefaults.standard.object(forKey: Self.lastCloudSyncAtKey) as? Date
        self.stateModifiedAt = Self.modificationDate(for: resolvedURL) ?? .distantPast
        self.iCloudSyncStatus = syncEnabled ? .checking : .disabled

        if syncEnabled {
            Task { await syncWithICloud() }
        }
    }

    deinit {
        cloudSyncTask?.cancel()
    }

    func saveProfile(_ profile: UserProfile) {
        state.profile = profile
        persist()
    }

    func setEnhancedLocalAnalysisEnabled(_ isEnabled: Bool) {
        state.preferences.enhancedLocalAnalysisEnabled = isEnabled
        persist()
    }

    func setTechnicalAttachmentMode(_ mode: TechnicalAttachmentMode) {
        state.preferences.technicalAttachmentMode = mode
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
        generatedTechnicalJSONURL: URL?,
        evidenceSHA256: String?
    ) throws -> URL {
        do {
            let caseDirectory = casesDirectory.appendingPathComponent(report.id.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: caseDirectory, withIntermediateDirectories: true)
            let pdfFileName = "Meldung-\(report.id.uuidString).pdf"
            let permanentPDFURL = caseDirectory.appendingPathComponent(pdfFileName)
            let pdfData = try Data(contentsOf: generatedPDFURL)
            try pdfData.write(to: permanentPDFURL, options: [.atomic, .completeFileProtection])

            let technicalJSONFileName = generatedTechnicalJSONURL.map { _ in
                "Technische-Daten-\(report.id.uuidString).json"
            }
            if let generatedTechnicalJSONURL, let technicalJSONFileName {
                let permanentJSONURL = caseDirectory.appendingPathComponent(technicalJSONFileName)
                let jsonData = try Data(contentsOf: generatedTechnicalJSONURL)
                try jsonData.write(to: permanentJSONURL, options: [.atomic, .completeFileProtection])
            }

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
                technicalJSONFileName: technicalJSONFileName,
                evidenceSHA256: evidenceSHA256,
                isCommonArea: report.isCommonArea,
                officialPropertyName: property.officialName,
                propertyType: property.propertyType
            )
            if let index = state.reportedCases.firstIndex(where: { $0.id == report.id }) {
                state.reportedCases[index] = storedCase
            } else {
                state.reportedCases.append(storedCase)
            }
            try persistState()
            scheduleCloudSync()
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

    func deleteReportedCase(_ id: UUID) {
        guard let index = state.reportedCases.firstIndex(where: { $0.id == id }) else { return }
        let removedCase = state.reportedCases.remove(at: index)

        do {
            try persistState()
            scheduleCloudSync()
        } catch {
            state.reportedCases.insert(removedCase, at: index)
            lastError = "Die Meldung konnte nicht gelöscht werden: \(error.localizedDescription)"
            return
        }

        do {
            try removeDirectoryIfPresent(casesDirectory.appendingPathComponent(id.uuidString, isDirectory: true))
            try removeDirectoryIfPresent(evidenceDirectory.appendingPathComponent(id.uuidString, isDirectory: true))
            lastError = nil
        } catch {
            lastError = "Die Meldung wurde aus der Liste gelöscht, aber nicht alle lokalen Dateien konnten entfernt werden: \(error.localizedDescription)"
        }
    }

    func pdfURL(for reportedCase: StoredReportedCase) -> URL? {
        let url = casesDirectory
            .appendingPathComponent(reportedCase.id.uuidString, isDirectory: true)
            .appendingPathComponent(reportedCase.pdfFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func technicalJSONURL(for reportedCase: StoredReportedCase) -> URL? {
        guard let fileName = reportedCase.technicalJSONFileName else { return nil }
        let url = casesDirectory
            .appendingPathComponent(reportedCase.id.uuidString, isDirectory: true)
            .appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func clearError() {
        lastError = nil
    }

    func setICloudSyncEnabled(_ isEnabled: Bool) {
        iCloudSyncEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: Self.cloudSyncEnabledKey)
        cloudSyncTask?.cancel()
        if isEnabled {
            iCloudSyncStatus = .checking
            Task { await syncWithICloud() }
        } else {
            iCloudSyncStatus = .disabled
        }
    }

    func syncWithICloud() async {
        guard iCloudSyncEnabled else {
            iCloudSyncStatus = .disabled
            return
        }

        guard !isCloudSyncInProgress else { return }
        isCloudSyncInProgress = true
        defer { isCloudSyncInProgress = false }
        iCloudSyncStatus = .syncing

        guard Self.hasCloudKitContainerEntitlement else {
            iCloudSyncStatus = .unavailable(
                "Dieser App-Build enthält keine gültige iCloud-Container-Berechtigung. Bitte installiere einen neu signierten Build."
            )
            return
        }

        do {
            guard try await cloudSyncService.accountIsAvailable() else {
                iCloudSyncStatus = .unavailable("Kein aktives iCloud-Konto")
                return
            }
            let result = try await cloudSyncService.synchronize(
                localState: state,
                localModifiedAt: stateModifiedAt,
                lastSyncAt: lastCloudSyncAt
            )
            state = result.state
            try persistState(markAsLocalChange: false)
            stateModifiedAt = result.synchronizedAt
            lastCloudSyncAt = result.synchronizedAt
            UserDefaults.standard.set(result.synchronizedAt, forKey: Self.lastCloudSyncAtKey)
            iCloudSyncStatus = .ready(lastSync: result.synchronizedAt)
        } catch {
            iCloudSyncStatus = .unavailable("iCloud-Fehler: \(error.localizedDescription)")
        }
    }

    func saveDraft(_ draft: IncidentDraft) {
        if !draft.hasMeaningfulContent {
            clearDraft()
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(draft).write(to: Self.draftURL(for: fileURL), options: [.atomic, .completeFileProtection])
            incidentDraft = draft
        } catch {
            lastError = "Der Entwurf konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    func clearDraft() {
        let url = Self.draftURL(for: fileURL)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            incidentDraft = nil
        } catch {
            lastError = "Der Entwurf konnte nicht entfernt werden: \(error.localizedDescription)"
        }
    }

    private func persist() {
        do {
            try persistState()
            lastError = nil
            scheduleCloudSync()
        } catch {
            lastError = "Die Einstellungen konnten nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    private func persistState(markAsLocalChange: Bool = true) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: fileURL, options: [.atomic, .completeFileProtection])
        if markAsLocalChange {
            stateModifiedAt = Date()
        }
    }

    private func scheduleCloudSync() {
        guard iCloudSyncEnabled else { return }
        cloudSyncTask?.cancel()
        cloudSyncTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.syncWithICloud()
        }
    }

    private var casesDirectory: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("Cases", isDirectory: true)
    }

    private var evidenceDirectory: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("Evidence", isDirectory: true)
    }

    private func removeDirectoryIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private static func load(from url: URL) -> AppDataState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(AppDataState.self, from: data) else {
            return AppDataState()
        }
        return state
    }

    private static func loadDraft(from url: URL) -> IncidentDraft? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(IncidentDraft.self, from: data)
    }

    private static func draftURL(for stateURL: URL) -> URL {
        stateURL.deletingLastPathComponent().appendingPathComponent("incident-draft.json")
    }

    private static var defaultFileURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("HVMeldeApp", isDirectory: true)
            .appendingPathComponent("app-data.json")
    }

    private static func modificationDate(for url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private static var hasCloudKitContainerEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.developer.icloud-container-identifiers" as CFString,
                nil
              ) else {
            return false
        }
        let identifiers = value as? [String] ?? []
        return identifiers.contains(CloudKitSyncService.containerIdentifier)
    }
}
