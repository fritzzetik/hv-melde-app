import Combine
import CryptoKit
import Foundation
import HVMeldeCore

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

    var activeReportCategories: [ReportCategory] {
        state.reportCategories
            .filter { $0.isEnabled && !$0.isDeleted }
            .sorted(by: Self.categorySort)
    }

    var configurableReportCategories: [ReportCategory] {
        state.reportCategories
            .filter { !$0.isDeleted }
            .sorted(by: Self.categorySort)
    }

    func upsertReportCategory(_ category: ReportCategory) {
        var category = category
        category.name = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
        category.defaultViolation = category.defaultViolation.trimmingCharacters(in: .whitespacesAndNewlines)
        if category.defaultViolation.isEmpty { category.defaultViolation = category.name }
        category.updatedAt = Date()
        if let index = state.reportCategories.firstIndex(where: { $0.id == category.id }) {
            state.reportCategories[index] = category
        } else {
            category.sortOrder = (state.reportCategories.map(\.sortOrder).max() ?? -1) + 1
            state.reportCategories.append(category)
        }
        persist()
    }

    func setReportCategoryEnabled(_ isEnabled: Bool, id: String) {
        guard let index = state.reportCategories.firstIndex(where: { $0.id == id }) else { return }
        if !isEnabled && activeReportCategories.count <= 1 { return }
        state.reportCategories[index].isEnabled = isEnabled
        state.reportCategories[index].updatedAt = Date()
        persist()
    }

    func deleteReportCategory(_ id: String) {
        guard let index = state.reportCategories.firstIndex(where: { $0.id == id }),
              !state.reportCategories[index].isBuiltIn else { return }
        state.reportCategories[index].isDeleted = true
        state.reportCategories[index].isEnabled = false
        state.reportCategories[index].updatedAt = Date()
        persist()
    }

    func moveReportCategories(from source: IndexSet, to destination: Int) {
        var categories = configurableReportCategories
        let moving = source.sorted().map { categories[$0] }
        for index in source.sorted(by: >) { categories.remove(at: index) }
        let removedBeforeDestination = source.filter { $0 < destination }.count
        let insertionIndex = min(max(destination - removedBeforeDestination, 0), categories.count)
        categories.insert(contentsOf: moving, at: insertionIndex)
        let now = Date()
        for (order, category) in categories.enumerated() {
            guard let index = state.reportCategories.firstIndex(where: { $0.id == category.id }) else { continue }
            state.reportCategories[index].sortOrder = order
            state.reportCategories[index].updatedAt = now
        }
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

    @discardableResult
    func createNoiseProtocol(
        property: ManagedProperty,
        title: String,
        suspectedSource: String,
        isCommonArea: Bool,
        requestsManagementResponse: Bool,
        allowsNameDisclosure: Bool
    ) -> UUID {
        let noiseProtocol = NoiseProtocol(
            propertyID: property.id,
            propertyName: property.displayName,
            officialPropertyName: property.officialName,
            propertyAddress: property.address,
            occupancyRole: property.occupancyRole,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Lärmprotokoll"
                : title.trimmingCharacters(in: .whitespacesAndNewlines),
            suspectedSource: suspectedSource.trimmingCharacters(in: .whitespacesAndNewlines),
            isCommonArea: isCommonArea,
            requestsManagementResponse: requestsManagementResponse,
            allowsNameDisclosure: allowsNameDisclosure
        )
        state.noiseProtocols.append(noiseProtocol)
        persist()
        return noiseProtocol.id
    }

    func addNoiseEntry(_ entry: NoiseTimelineEntry, to protocolID: UUID) {
        guard let index = state.noiseProtocols.firstIndex(where: { $0.id == protocolID }) else { return }
        state.noiseProtocols[index].entries.append(entry)
        state.noiseProtocols[index].entries.sort { $0.startedAt < $1.startedAt }
        state.noiseProtocols[index].updatedAt = Date()
        persist()
    }

    func finishNoiseDisturbance(
        protocolID: UUID,
        entryID: UUID,
        at endedAt: Date = Date()
    ) {
        guard let protocolIndex = state.noiseProtocols.firstIndex(where: { $0.id == protocolID }),
              let entryIndex = state.noiseProtocols[protocolIndex].entries.firstIndex(where: { $0.id == entryID }),
              state.noiseProtocols[protocolIndex].entries[entryIndex].kind == .disturbance else {
            return
        }
        let start = state.noiseProtocols[protocolIndex].entries[entryIndex].startedAt
        state.noiseProtocols[protocolIndex].entries[entryIndex].endedAt = max(start, endedAt)
        state.noiseProtocols[protocolIndex].entries[entryIndex].updatedAt = Date()
        state.noiseProtocols[protocolIndex].updatedAt = Date()
        persist()
    }

    func setNoiseProtocolStatus(_ status: NoiseProtocolStatus, for protocolID: UUID) {
        guard let index = state.noiseProtocols.firstIndex(where: { $0.id == protocolID }) else { return }
        state.noiseProtocols[index].status = status
        state.noiseProtocols[index].completedAt = status == .completed ? Date() : nil
        state.noiseProtocols[index].updatedAt = Date()
        persist()
    }

    func deleteNoiseProtocol(_ protocolID: UUID) {
        guard let index = state.noiseProtocols.firstIndex(where: { $0.id == protocolID }) else { return }
        let previousState = state
        state.noiseProtocols.remove(at: index)
        do {
            try persistState()
            try NoiseEvidenceStore.removeProtocol(protocolID)
            scheduleCloudSync()
        } catch {
            state = previousState
            lastError = "Das Lärmprotokoll konnte nicht gelöscht werden: \(error.localizedDescription)"
        }
    }

    func noiseEvidenceURL(for evidence: NoiseEvidenceFile, protocolID: UUID) -> URL? {
        let url = NoiseEvidenceStore.localURL(for: evidence, protocolID: protocolID)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func saveReportedCase(
        report: IncidentReport,
        category: ReportCategory,
        property: ManagedProperty,
        generatedPDFURL: URL,
        generatedTechnicalJSONURL: URL?,
        evidenceSHA256: String?,
        evidencePhotos: [EvidencePhoto]
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

            var cloudFiles = [CloudCaseFileReference(
                id: report.id,
                caseID: report.id,
                kind: .pdf,
                fileName: pdfFileName,
                sha256: Self.sha256(pdfData),
                createdAt: report.createdAt
            )]
            if let technicalJSONFileName {
                let jsonURL = caseDirectory.appendingPathComponent(technicalJSONFileName)
                let jsonData = try Data(contentsOf: jsonURL)
                cloudFiles.append(CloudCaseFileReference(
                    id: report.id,
                    caseID: report.id,
                    kind: .technicalJSON,
                    fileName: technicalJSONFileName,
                    sha256: Self.sha256(jsonData),
                    createdAt: report.createdAt
                ))
            }
            for photo in evidencePhotos {
                cloudFiles.append(CloudCaseFileReference(
                    id: photo.id,
                    caseID: report.id,
                    kind: .photo,
                    fileName: photo.localURL.lastPathComponent,
                    sha256: photo.sha256,
                    createdAt: photo.importedAt,
                    metadata: try EvidencePhotoStore.cloudMetadataData(for: photo)
                ))
            }

            let existing = state.reportedCases.first { $0.id == report.id }
            let newRecordNames = Set(cloudFiles.map(\.recordName))
            let obsoleteRecordNames = Set(existing?.cloudFiles?.map(\.recordName) ?? [])
                .subtracting(newRecordNames)
            state.deletedCloudFileRecordNames = Array(
                Set(state.deletedCloudFileRecordNames).union(obsoleteRecordNames)
            ).sorted()
            state.deletedCases.removeAll { $0.id == report.id }
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
                propertyType: property.propertyType,
                cloudFiles: cloudFiles,
                requestsManagementResponse: report.wantsManagementResponse,
                allowsNameDisclosure: report.permitsNameDisclosure
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
        let previousState = state
        let removedCase = state.reportedCases.remove(at: index)
        state.deletedCases.removeAll { $0.id == id }
        state.deletedCases.append(DeletedCaseTombstone(id: id))
        state.deletedCloudFileRecordNames = Array(
            Set(state.deletedCloudFileRecordNames)
                .union(removedCase.cloudFiles?.map(\.recordName) ?? [])
        ).sorted()

        do {
            try persistState()
            scheduleCloudSync()
        } catch {
            state = previousState
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

        do {
            guard try await cloudSyncService.accountIsAvailable() else {
                iCloudSyncStatus = .unavailable("Kein aktives iCloud-Konto")
                return
            }
            try await prepareCloudFileManifests()
            let previousCaseIDs = Set(state.reportedCases.map(\.id))
            let result = try await cloudSyncService.synchronize(
                localState: state,
                localModifiedAt: stateModifiedAt,
                lastSyncAt: lastCloudSyncAt
            )
            state = result.state
            try persistState(markAsLocalChange: false)
            let removedCaseIDs = previousCaseIDs.subtracting(state.reportedCases.map(\.id))
            for id in removedCaseIDs {
                try removeDirectoryIfPresent(casesDirectory.appendingPathComponent(id.uuidString, isDirectory: true))
                try removeDirectoryIfPresent(evidenceDirectory.appendingPathComponent(id.uuidString, isDirectory: true))
            }
            try await cloudSyncService.synchronizeFiles(in: state, baseDirectory: baseDirectory)
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

    private var baseDirectory: URL {
        fileURL.deletingLastPathComponent()
    }

    private func prepareCloudFileManifests() async throws {
        var changed = false
        for index in state.reportedCases.indices where state.reportedCases[index].cloudFiles == nil {
            let reportedCase = state.reportedCases[index]
            var references: [CloudCaseFileReference] = []
            if let pdfURL = pdfURL(for: reportedCase) {
                let data = try Data(contentsOf: pdfURL)
                references.append(CloudCaseFileReference(
                    id: reportedCase.id,
                    caseID: reportedCase.id,
                    kind: .pdf,
                    fileName: reportedCase.pdfFileName,
                    sha256: Self.sha256(data),
                    createdAt: reportedCase.createdAt
                ))
            }
            if let jsonURL = technicalJSONURL(for: reportedCase) {
                let data = try Data(contentsOf: jsonURL)
                references.append(CloudCaseFileReference(
                    id: reportedCase.id,
                    caseID: reportedCase.id,
                    kind: .technicalJSON,
                    fileName: jsonURL.lastPathComponent,
                    sha256: Self.sha256(data),
                    createdAt: reportedCase.createdAt
                ))
            }
            let photos = try await EvidencePhotoStore.loadAll(for: reportedCase.id)
            for photo in photos {
                references.append(CloudCaseFileReference(
                    id: photo.id,
                    caseID: reportedCase.id,
                    kind: .photo,
                    fileName: photo.localURL.lastPathComponent,
                    sha256: photo.sha256,
                    createdAt: photo.importedAt,
                    metadata: try EvidencePhotoStore.cloudMetadataData(for: photo)
                ))
            }
            guard !references.isEmpty else { continue }
            state.reportedCases[index].cloudFiles = references
            state.reportedCases[index].updatedAt = Date()
            changed = true
        }
        if changed {
            try persistState()
        }
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

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func categorySort(_ lhs: ReportCategory, _ rhs: ReportCategory) -> Bool {
        if lhs.sortOrder == rhs.sortOrder {
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return lhs.sortOrder < rhs.sortOrder
    }

}
