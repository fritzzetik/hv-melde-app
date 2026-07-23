import AVFoundation
import CryptoKit
import Foundation
import HVMeldeCore

enum NoiseEvidenceStore {
    static func storeVideo(
        from sourceURL: URL,
        protocolID: UUID,
        entryID: UUID,
        originalFileName: String? = nil
    ) async throws -> NoiseEvidenceFile {
        let importedAt = Date()
        let asset = AVURLAsset(url: sourceURL)
        let duration = try? await asset.load(.duration)
        let capturedAt = await videoCreationDate(from: asset)
        let fileID = UUID()
        let sourceExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension.lowercased()
        let storedFileName = "evidence-\(fileID.uuidString.lowercased()).\(sourceExtension)"
        let directory = try entryDirectory(protocolID: protocolID, entryID: entryID)
        let destinationURL = directory.appendingPathComponent(storedFileName)

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        try (destinationURL as NSURL).setResourceValue(
            URLFileProtection.complete,
            forKey: .fileProtectionKey
        )

        let attributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
        let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        return try NoiseEvidenceFile(
            id: fileID,
            entryID: entryID,
            kind: .video,
            originalFileName: originalFileName ?? sourceURL.lastPathComponent,
            storedFileName: storedFileName,
            sha256: sha256(of: destinationURL),
            capturedAt: capturedAt,
            importedAt: importedAt,
            durationSeconds: duration.map(CMTimeGetSeconds).flatMap { $0.isFinite ? $0 : nil },
            byteCount: byteCount
        )
    }

    static func localURL(
        for evidence: NoiseEvidenceFile,
        protocolID: UUID
    ) -> URL {
        baseDirectory
            .appendingPathComponent(protocolID.uuidString, isDirectory: true)
            .appendingPathComponent("Evidence", isDirectory: true)
            .appendingPathComponent(evidence.entryID.uuidString, isDirectory: true)
            .appendingPathComponent(evidence.storedFileName)
    }

    static func removeDraftEvidence(protocolID: UUID, entryID: UUID) throws {
        let url = baseDirectory
            .appendingPathComponent(protocolID.uuidString, isDirectory: true)
            .appendingPathComponent("Evidence", isDirectory: true)
            .appendingPathComponent(entryID.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    static func removeEvidence(_ evidence: NoiseEvidenceFile, protocolID: UUID) throws {
        let url = localURL(for: evidence, protocolID: protocolID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    static func removeProtocol(_ protocolID: UUID) throws {
        let url = baseDirectory.appendingPathComponent(protocolID.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private static func entryDirectory(protocolID: UUID, entryID: UUID) throws -> URL {
        let url = baseDirectory
            .appendingPathComponent(protocolID.uuidString, isDirectory: true)
            .appendingPathComponent("Evidence", isDirectory: true)
            .appendingPathComponent(entryID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var baseDirectory: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("HVMeldeApp", isDirectory: true)
            .appendingPathComponent("NoiseProtocols", isDirectory: true)
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func videoCreationDate(from asset: AVURLAsset) async -> Date? {
        guard let metadata = try? await asset.load(.commonMetadata) else { return nil }
        for item in metadata where item.commonKey == .commonKeyCreationDate {
            guard let value = try? await item.load(.stringValue) else { continue }
            if let date = ISO8601DateFormatter().date(from: value) {
                return date
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }
}
