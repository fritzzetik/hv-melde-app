import CloudKit
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

        guard let payload = existingRecord["payload"] as? Data else {
            throw CloudSyncError.invalidCloudData
        }
        let remoteState = try decoder.decode(AppDataState.self, from: payload)
        let remoteModifiedAt = existingRecord["stateModifiedAt"] as? Date
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
        record["payload"] = try encoder.encode(state) as CKRecordValue
        record["stateModifiedAt"] = modifiedAt as CKRecordValue
        record["schemaVersion"] = NSNumber(value: 1)
    }

    private func hasLocalContent(_ state: AppDataState) -> Bool {
        !state.profile.fullName.isEmpty
            || !state.properties.isEmpty
            || !state.propertyManagements.isEmpty
            || !state.reportedCases.isEmpty
    }

    private func merge(local: AppDataState, remote: AppDataState) -> AppDataState {
        var properties = Dictionary(uniqueKeysWithValues: remote.properties.map { ($0.id, $0) })
        local.properties.forEach { properties[$0.id] = $0 }

        var managements = Dictionary(uniqueKeysWithValues: remote.propertyManagements.map { ($0.id, $0) })
        local.propertyManagements.forEach { managements[$0.id] = $0 }

        var cases = Dictionary(uniqueKeysWithValues: remote.reportedCases.map { ($0.id, $0) })
        for reportedCase in local.reportedCases {
            if let remoteCase = cases[reportedCase.id], remoteCase.updatedAt > reportedCase.updatedAt {
                continue
            }
            cases[reportedCase.id] = reportedCase
        }

        let profile = local.profile.fullName.isEmpty ? remote.profile : local.profile
        return AppDataState(
            profile: profile,
            properties: properties.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending },
            propertyManagements: managements.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            reportedCases: cases.values.sorted { $0.createdAt > $1.createdAt },
            preferences: local.preferences
        )
    }
}

private enum CloudSyncError: LocalizedError {
    case invalidCloudData

    var errorDescription: String? {
        "Die in iCloud gespeicherten App-Daten konnten nicht gelesen werden. Die lokalen Daten wurden nicht verändert."
    }
}
