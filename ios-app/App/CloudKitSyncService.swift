import CloudKit
import CryptoKit
import Foundation
import HVMeldeCore

enum ICloudSyncStatus: Equatable {
    case disabled
    case checking
    case ready(lastSync: Date?)
    case syncing
    case unavailable(String)

    var title: String {
        switch self {
        case .disabled: "Deaktiviert"
        case .checking: "iCloud wird geprüft …"
        case .ready(let lastSync):
            if let lastSync {
                "Zuletzt synchronisiert: \(lastSync.formatted(date: .abbreviated, time: .shortened))"
            } else {
                "Bereit zur ersten Synchronisierung"
            }
        case .syncing: "Synchronisierung läuft …"
        case .unavailable(let message): message
        }
    }
}

struct CloudSyncResult: Sendable {
    let state: AppDataState
    let synchronizedAt: Date
}

@MainActor
final class CloudKitSyncService {
    static let containerIdentifier = "iCloud.at.zetik.hvmeldeapp"

    private let container: CKContainer
    private let database: CKDatabase
    private let recordID = CKRecord.ID(recordName: "primary-app-data")
    private let recordType = "AppDataSnapshot"

    init() {
        // The default container is resolved from the signed app entitlements. Creating
        // a container from a hard-coded identifier traps before errors can be handled
        // when a distribution profile doesn't expose that identifier exactly.
        container = CKContainer.default()
        database = container.privateCloudDatabase
    }

    func accountIsAvailable() async throws -> Bool {
        try await container.accountStatus() == .available
    }

    func synchronize(
        localState: AppDataState,
        localModifiedAt: Date,
        lastSyncAt: Date?
    ) async throws -> CloudSyncResult {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let existingRecord = try await fetchRecordIfPresent()
        guard let existingRecord else {
            let record = CKRecord(recordType: recordType, recordID: recordID)
            try setPayload(localState, modifiedAt: localModifiedAt, on: record, encoder: encoder)
            let saved = try await database.save(record)
            return CloudSyncResult(state: localState, synchronizedAt: saved.modificationDate ?? Date())
        }

        guard let payload = existingRecord.encryptedValues["payload"] as? Data else {
            throw CloudSyncError.invalidCloudData
        }
        let remoteState = try decoder.decode(AppDataState.self, from: payload)
        let remoteModifiedAt = existingRecord.encryptedValues["stateModifiedAt"] as? Date
            ?? existingRecord.modificationDate
            ?? .distantPast

        let localChanged = lastSyncAt.map { localModifiedAt > $0 } ?? hasLocalContent(localState)
        let remoteChanged = lastSyncAt.map { remoteModifiedAt > $0 } ?? true

        if localChanged && remoteChanged {
            let merged = merge(local: localState, remote: remoteState)
            try setPayload(merged, modifiedAt: Date(), on: existingRecord, encoder: encoder)
            let saved = try await database.save(existingRecord)
            return CloudSyncResult(state: merged, synchronizedAt: saved.modificationDate ?? Date())
        }

        if localChanged {
            try setPayload(localState, modifiedAt: localModifiedAt, on: existingRecord, encoder: encoder)
            let saved = try await database.save(existingRecord)
            return CloudSyncResult(state: localState, synchronizedAt: saved.modificationDate ?? Date())
        }

        return CloudSyncResult(state: remoteState, synchronizedAt: existingRecord.modificationDate ?? Date())
    }

    func synchronizeFiles(in state: AppDataState, baseDirectory: URL) async throws {
        let deletedRecordNames = Set(state.deletedCloudFileRecordNames)
        for recordName in deletedRecordNames {
            do {
                _ = try await database.deleteRecord(withID: CKRecord.ID(recordName: recordName))
            } catch let error as CKError where error.code == .unknownItem {
                // Repeating a completed deletion is harmless and keeps offline deletions durable.
            }
        }

        for reportedCase in state.reportedCases {
            for reference in reportedCase.cloudFiles ?? [] where !deletedRecordNames.contains(reference.recordName) {
                try await synchronizeFile(reference, caseID: reportedCase.id, baseDirectory: baseDirectory)
            }
        }
    }

    private func fetchRecordIfPresent() async throws -> CKRecord? {
        do {
            return try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func setPayload(
        _ state: AppDataState,
        modifiedAt: Date,
        on record: CKRecord,
        encoder: JSONEncoder
    ) throws {
        record.encryptedValues["payload"] = try encoder.encode(state) as CKRecordValue
        record.encryptedValues["stateModifiedAt"] = modifiedAt as CKRecordValue
        record.encryptedValues["schemaVersion"] = NSNumber(value: 5)
    }

    private func hasLocalContent(_ state: AppDataState) -> Bool {
        !state.profile.fullName.isEmpty
            || !state.properties.isEmpty
            || !state.propertyManagements.isEmpty
            || !state.reportedCases.isEmpty
            || !state.noiseProtocols.isEmpty
            || state.reportCategories != ReportCategory.defaultCategories
            || state.preferences != AppPreferences()
    }

    private func merge(local: AppDataState, remote: AppDataState) -> AppDataState {
        var properties = Dictionary(uniqueKeysWithValues: remote.properties.map { ($0.id, $0) })
        local.properties.forEach { properties[$0.id] = $0 }

        var managements = Dictionary(uniqueKeysWithValues: remote.propertyManagements.map { ($0.id, $0) })
        local.propertyManagements.forEach { managements[$0.id] = $0 }

        var cases = Dictionary(uniqueKeysWithValues: remote.reportedCases.map { ($0.id, $0) })
        for reportedCase in local.reportedCases {
            if let remoteCase = cases[reportedCase.id], remoteCase.updatedAt > reportedCase.updatedAt {
                if remoteCase.cloudFiles == nil, let localFiles = reportedCase.cloudFiles {
                    var enrichedRemoteCase = remoteCase
                    enrichedRemoteCase.cloudFiles = localFiles
                    cases[reportedCase.id] = enrichedRemoteCase
                }
                continue
            }
            var mergedCase = reportedCase
            if mergedCase.cloudFiles == nil {
                mergedCase.cloudFiles = cases[reportedCase.id]?.cloudFiles
            }
            cases[reportedCase.id] = mergedCase
        }

        var deletedCases = Dictionary(uniqueKeysWithValues: remote.deletedCases.map { ($0.id, $0) })
        for tombstone in local.deletedCases {
            if let remoteTombstone = deletedCases[tombstone.id], remoteTombstone.deletedAt > tombstone.deletedAt {
                continue
            }
            deletedCases[tombstone.id] = tombstone
        }
        cases = cases.filter { id, _ in deletedCases[id] == nil }

        let deletedRecordNames = Set(local.deletedCloudFileRecordNames)
            .union(remote.deletedCloudFileRecordNames)

        var categories = Dictionary(uniqueKeysWithValues: remote.reportCategories.map { ($0.id, $0) })
        for category in local.reportCategories {
            if let remoteCategory = categories[category.id], remoteCategory.updatedAt > category.updatedAt {
                continue
            }
            categories[category.id] = category
        }

        var noiseProtocols = Dictionary(uniqueKeysWithValues: remote.noiseProtocols.map { ($0.id, $0) })
        for noiseProtocol in local.noiseProtocols {
            if let remoteProtocol = noiseProtocols[noiseProtocol.id],
               remoteProtocol.updatedAt > noiseProtocol.updatedAt {
                continue
            }
            noiseProtocols[noiseProtocol.id] = noiseProtocol
        }

        let profile = local.profile.fullName.isEmpty ? remote.profile : local.profile
        return AppDataState(
            profile: profile,
            properties: properties.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending },
            propertyManagements: managements.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            reportedCases: cases.values.sorted { $0.createdAt > $1.createdAt },
            reportCategories: categories.values.sorted {
                if $0.sortOrder == $1.sortOrder { return $0.name < $1.name }
                return $0.sortOrder < $1.sortOrder
            },
            preferences: local.preferences,
            deletedCases: deletedCases.values.sorted { $0.deletedAt < $1.deletedAt },
            deletedCloudFileRecordNames: deletedRecordNames.sorted(),
            noiseProtocols: noiseProtocols.values.sorted { $0.updatedAt > $1.updatedAt }
        )
    }

    private func synchronizeFile(
        _ reference: CloudCaseFileReference,
        caseID: UUID,
        baseDirectory: URL
    ) async throws {
        let localURL = try localURL(for: reference, caseID: caseID, baseDirectory: baseDirectory)
        let recordID = CKRecord.ID(recordName: reference.recordName)
        let remoteRecord: CKRecord?
        do {
            remoteRecord = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            remoteRecord = nil
        }

        if FileManager.default.fileExists(atPath: localURL.path) {
            let remoteHash = remoteRecord?.encryptedValues["sha256"] as? String
            guard remoteHash != reference.sha256 else { return }
            let record = remoteRecord ?? CKRecord(recordType: "CaseFile", recordID: recordID)
            record["file"] = CKAsset(fileURL: localURL)
            record.encryptedValues["caseID"] = caseID.uuidString as CKRecordValue
            record.encryptedValues["fileID"] = reference.id.uuidString as CKRecordValue
            record.encryptedValues["kind"] = reference.kind.rawValue as CKRecordValue
            record.encryptedValues["fileName"] = reference.fileName as CKRecordValue
            record.encryptedValues["sha256"] = reference.sha256 as CKRecordValue
            record.encryptedValues["createdAt"] = reference.createdAt as CKRecordValue
            if let metadata = reference.metadata {
                record.encryptedValues["metadata"] = metadata as CKRecordValue
            } else {
                record.encryptedValues["metadata"] = nil
            }
            _ = try await database.save(record)
            return
        }

        guard let asset = remoteRecord?["file"] as? CKAsset, let assetURL = asset.fileURL else {
            return
        }
        let data = try Data(contentsOf: assetURL)
        guard Self.sha256(data) == reference.sha256 else {
            throw CloudSyncError.fileChecksumMismatch(reference.fileName)
        }
        try FileManager.default.createDirectory(
            at: localURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: localURL, options: [.atomic, .completeFileProtection])
        if reference.kind == .photo, let metadata = reference.metadata {
            let metadataURL = localURL.deletingLastPathComponent()
                .appendingPathComponent("metadata-\(reference.id.uuidString).json")
            try metadata.write(to: metadataURL, options: [.atomic, .completeFileProtection])
        }
    }

    private func localURL(
        for reference: CloudCaseFileReference,
        caseID: UUID,
        baseDirectory: URL
    ) throws -> URL {
        guard reference.fileName == URL(fileURLWithPath: reference.fileName).lastPathComponent,
              !reference.fileName.contains("/") && !reference.fileName.contains("\\") else {
            throw CloudSyncError.invalidFileName
        }
        let folder = reference.kind == .photo ? "Evidence" : "Cases"
        return baseDirectory
            .appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent(caseID.uuidString, isDirectory: true)
            .appendingPathComponent(reference.fileName)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private enum CloudSyncError: LocalizedError {
    case invalidCloudData
    case invalidFileName
    case fileChecksumMismatch(String)

    var errorDescription: String? {
        switch self {
        case .invalidCloudData:
            "Die in iCloud gespeicherten App-Daten konnten nicht gelesen werden. Die lokalen Daten wurden nicht verändert."
        case .invalidFileName:
            "Eine in iCloud gespeicherte Datei hat einen ungültigen Namen."
        case .fileChecksumMismatch(let fileName):
            "Die Prüfsumme der iCloud-Datei \(fileName) stimmt nicht. Die lokale Datei wurde nicht ersetzt."
        }
    }
}
