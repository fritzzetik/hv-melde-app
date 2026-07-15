import CryptoKit
import Foundation
import HVMeldeCore

enum EvidencePhotoSource: String, Codable, Sendable {
    case photoLibrary = "Fotomediathek"
    case camera = "Kamera"
}

struct ConfirmedImageAnalysis: Codable, Equatable, Sendable {
    let category: ReportCategory
    let vehicleDetected: Bool
    let vehicleConfidence: Float
    let confirmedLicensePlate: String
    let confirmedVehicleDescription: String
    let confirmedSceneSummary: String
    let analyzedAt: Date
    let analyzerDescription: String
}

struct EvidencePhoto: Identifiable, Sendable {
    let id: UUID
    let reportID: UUID
    let localURL: URL
    let data: Data
    let sha256: String
    let importedAt: Date
    let source: EvidencePhotoSource
    let imageTimestamp: EvidenceImageTimestamp
    var confirmedAnalysis: ConfirmedImageAnalysis?
}

private struct EvidencePhotoMetadata: Codable, Sendable {
    let id: UUID
    let reportID: UUID
    let fileName: String
    let sha256: String
    let importedAt: Date
    let source: EvidencePhotoSource
    let imageTimestamp: EvidenceImageTimestamp
    let confirmedAnalysis: ConfirmedImageAnalysis?
}

enum EvidencePhotoStore {
    static func store(
        data: Data,
        reportID: UUID,
        source: EvidencePhotoSource,
        fileExtension: String?
    ) async throws -> EvidencePhoto {
        try await Task.detached(priority: .userInitiated) {
            let id = UUID()
            let importedAt = Date()
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let imageTimestamp = EvidenceImageMetadataReader.read(
                from: data,
                photoSource: source,
                importedAt: importedAt
            )
            let directory = try evidenceDirectory(for: reportID)
            let sanitizedExtension = sanitize(fileExtension) ?? "jpg"
            let fileName = "original-\(id.uuidString).\(sanitizedExtension)"
            let localURL = directory.appendingPathComponent(fileName)

            try data.write(to: localURL, options: [.atomic, .completeFileProtection])

            let photo = EvidencePhoto(
                id: id,
                reportID: reportID,
                localURL: localURL,
                data: data,
                sha256: digest,
                importedAt: importedAt,
                source: source,
                imageTimestamp: imageTimestamp,
                confirmedAnalysis: nil
            )
            try writeMetadata(for: photo)
            return photo
        }.value
    }

    static func updateMetadata(for photo: EvidencePhoto) async throws {
        try await Task.detached(priority: .utility) {
            try writeMetadata(for: photo)
        }.value
    }

    private static func evidenceDirectory(for reportID: UUID) throws -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = baseURL
            .appendingPathComponent("HVMeldeApp", isDirectory: true)
            .appendingPathComponent("Evidence", isDirectory: true)
            .appendingPathComponent(reportID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func writeMetadata(for photo: EvidencePhoto) throws {
        let metadata = EvidencePhotoMetadata(
            id: photo.id,
            reportID: photo.reportID,
            fileName: photo.localURL.lastPathComponent,
            sha256: photo.sha256,
            importedAt: photo.importedAt,
            source: photo.source,
            imageTimestamp: photo.imageTimestamp,
            confirmedAnalysis: photo.confirmedAnalysis
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let metadataURL = photo.localURL
            .deletingLastPathComponent()
            .appendingPathComponent("metadata-\(photo.id.uuidString).json")
        try encoder.encode(metadata).write(to: metadataURL, options: [.atomic, .completeFileProtection])
    }

    private static func sanitize(_ fileExtension: String?) -> String? {
        guard let fileExtension else { return nil }
        let value = fileExtension.lowercased().filter { $0.isLetter || $0.isNumber }
        return value.isEmpty ? nil : String(value.prefix(8))
    }
}
