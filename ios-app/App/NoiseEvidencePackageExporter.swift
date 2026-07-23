import CryptoKit
import Foundation
import HVMeldeCore

@MainActor
enum NoiseEvidencePackageExporter {
    static func create(
        noiseProtocol: NoiseProtocol,
        profile: UserProfile,
        management: PropertyManagement?,
        evidenceURL: (NoiseEvidenceFile) -> URL?
    ) async throws -> URL {
        let pdfURL = try NoiseProtocolPDFRenderer.render(
            noiseProtocol: noiseProtocol,
            profile: profile,
            management: management,
            evidenceURL: evidenceURL
        )
        let index = NoiseProtocolEvidenceIndex(noiseProtocol: noiseProtocol)
        let packageID = UUID()
        let packageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("noise-package-\(packageID.uuidString)", isDirectory: true)
        try? FileManager.default.removeItem(at: packageDirectory)
        try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)

        let pdfName = "Laermprotokoll-\(noiseProtocol.id.uuidString).pdf"
        let packagePDFURL = packageDirectory.appendingPathComponent(pdfName)
        try FileManager.default.copyItem(at: pdfURL, to: packagePDFURL)

        var archiveEntries = [ZIPArchiveWriter.Entry(name: pdfName, url: packagePDFURL)]
        var manifestFiles = [
            EvidencePackageManifest.FileItem(
                attachmentNumber: nil,
                entryNumber: nil,
                kind: "pdf",
                exportFileName: pdfName,
                originalFileName: pdfURL.lastPathComponent,
                sha256: try sha256(of: packagePDFURL),
                byteCount: try fileSize(packagePDFURL),
                capturedAt: nil,
                importedAt: Date(),
                durationSeconds: nil
            )
        ]

        for item in index.evidence {
            guard let sourceURL = evidenceURL(item.evidence),
                  FileManager.default.fileExists(atPath: sourceURL.path) else {
                throw ExportError.missingEvidence(item.evidence.originalFileName)
            }
            archiveEntries.append(ZIPArchiveWriter.Entry(name: item.exportFileName, url: sourceURL))
            manifestFiles.append(EvidencePackageManifest.FileItem(
                attachmentNumber: item.attachmentNumber,
                entryNumber: item.entryNumber,
                kind: item.evidence.kind.rawValue,
                exportFileName: item.exportFileName,
                originalFileName: item.evidence.originalFileName,
                sha256: item.evidence.sha256,
                byteCount: item.evidence.byteCount,
                capturedAt: item.evidence.capturedAt,
                importedAt: item.evidence.importedAt,
                durationSeconds: item.evidence.durationSeconds
            ))
        }

        let manifest = EvidencePackageManifest(
            schemaVersion: 1,
            packageID: packageID,
            createdAt: Date(),
            protocolID: noiseProtocol.id,
            title: noiseProtocol.title,
            propertyName: noiseProtocol.recipientPropertyName,
            propertyAddress: noiseProtocol.propertyAddress.formatted,
            suspectedSource: noiseProtocol.suspectedSource,
            status: noiseProtocol.status.rawValue,
            entries: index.entries.map { item in
                EvidencePackageManifest.EntryItem(
                    number: item.number,
                    id: item.entry.id,
                    kind: item.entry.kind.rawValue,
                    startedAt: item.entry.startedAt,
                    endedAt: item.entry.endedAt,
                    summary: item.entry.kind == .disturbance
                        ? item.entry.noiseType
                        : item.entry.responderType,
                    details: item.entry.details
                )
            },
            files: manifestFiles
        )
        let manifestURL = packageDirectory.appendingPathComponent("manifest.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: manifestURL, options: [.atomic, .completeFileProtection])
        archiveEntries.insert(ZIPArchiveWriter.Entry(name: "manifest.json", url: manifestURL), at: 1)

        let period = periodFileName(noiseProtocol)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Beweispaket-\(period)-\(noiseProtocol.id.uuidString.prefix(8)).zip")
        try? FileManager.default.removeItem(at: outputURL)
        try ZIPArchiveWriter.create(entries: archiveEntries, at: outputURL)
        try (outputURL as NSURL).setResourceValue(URLFileProtection.complete, forKey: .fileProtectionKey)
        try? FileManager.default.removeItem(at: packageDirectory)
        return outputURL
    }

    private static func periodFileName(_ noiseProtocol: NoiseProtocol) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        guard let first = noiseProtocol.firstEventAt else { return formatter.string(from: Date()) }
        let last = noiseProtocol.lastEventAt ?? first
        return "\(formatter.string(from: first))-\(formatter.string(from: last))"
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

    private static func fileSize(_ url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }
}

private struct EvidencePackageManifest: Codable {
    struct EntryItem: Codable {
        let number: String
        let id: UUID
        let kind: String
        let startedAt: Date
        let endedAt: Date?
        let summary: String
        let details: String
    }

    struct FileItem: Codable {
        let attachmentNumber: String?
        let entryNumber: String?
        let kind: String
        let exportFileName: String
        let originalFileName: String
        let sha256: String
        let byteCount: Int64
        let capturedAt: Date?
        let importedAt: Date
        let durationSeconds: Double?
    }

    let schemaVersion: Int
    let packageID: UUID
    let createdAt: Date
    let protocolID: UUID
    let title: String
    let propertyName: String
    let propertyAddress: String
    let suspectedSource: String
    let status: String
    let entries: [EntryItem]
    let files: [FileItem]
}

private enum ExportError: LocalizedError {
    case missingEvidence(String)

    var errorDescription: String? {
        switch self {
        case .missingEvidence(let name):
            "Die Beweisdatei \(name) ist auf diesem Gerät nicht verfügbar. Das Paket wurde nicht erstellt."
        }
    }
}

private enum ZIPArchiveWriter {
    struct Entry {
        let name: String
        let url: URL
    }

    private struct CentralEntry {
        let nameData: Data
        let crc32: UInt32
        let size: UInt32
        let localHeaderOffset: UInt32
        let modificationDate: Date
    }

    static func create(entries: [Entry], at outputURL: URL) throws {
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }
        var centralEntries: [CentralEntry] = []

        for entry in entries {
            let attributes = try FileManager.default.attributesOfItem(atPath: entry.url.path)
            let expectedSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            guard expectedSize <= UInt64(UInt32.max),
                  output.offsetInFile <= UInt64(UInt32.max) else {
                throw ZIPError.archiveTooLarge
            }
            let nameData = Data(entry.name.utf8)
            guard nameData.count <= Int(UInt16.max) else { throw ZIPError.invalidFileName }
            let localHeaderOffset = UInt32(output.offsetInFile)
            let modificationDate = (attributes[.modificationDate] as? Date) ?? Date()
            let dos = dosDateTime(modificationDate)

            try output.writeLE(UInt32(0x04034b50))
            try output.writeLE(UInt16(20))
            try output.writeLE(UInt16(0x0808))
            try output.writeLE(UInt16(0))
            try output.writeLE(dos.time)
            try output.writeLE(dos.date)
            try output.writeLE(UInt32(0))
            try output.writeLE(UInt32(0))
            try output.writeLE(UInt32(0))
            try output.writeLE(UInt16(nameData.count))
            try output.writeLE(UInt16(0))
            try output.write(contentsOf: nameData)

            let input = try FileHandle(forReadingFrom: entry.url)
            var crc = CRC32()
            var actualSize: UInt64 = 0
            do {
                while let data = try input.read(upToCount: 1_048_576), !data.isEmpty {
                    actualSize += UInt64(data.count)
                    guard actualSize <= UInt64(UInt32.max) else { throw ZIPError.archiveTooLarge }
                    crc.update(data)
                    try output.write(contentsOf: data)
                }
                try input.close()
            } catch {
                try? input.close()
                throw error
            }
            let size = UInt32(actualSize)
            let checksum = crc.finalize()
            try output.writeLE(UInt32(0x08074b50))
            try output.writeLE(checksum)
            try output.writeLE(size)
            try output.writeLE(size)
            centralEntries.append(CentralEntry(
                nameData: nameData,
                crc32: checksum,
                size: size,
                localHeaderOffset: localHeaderOffset,
                modificationDate: modificationDate
            ))
        }

        guard centralEntries.count <= Int(UInt16.max),
              output.offsetInFile <= UInt64(UInt32.max) else {
            throw ZIPError.archiveTooLarge
        }
        let centralOffset = UInt32(output.offsetInFile)
        for entry in centralEntries {
            let dos = dosDateTime(entry.modificationDate)
            try output.writeLE(UInt32(0x02014b50))
            try output.writeLE(UInt16(20))
            try output.writeLE(UInt16(20))
            try output.writeLE(UInt16(0x0808))
            try output.writeLE(UInt16(0))
            try output.writeLE(dos.time)
            try output.writeLE(dos.date)
            try output.writeLE(entry.crc32)
            try output.writeLE(entry.size)
            try output.writeLE(entry.size)
            try output.writeLE(UInt16(entry.nameData.count))
            try output.writeLE(UInt16(0))
            try output.writeLE(UInt16(0))
            try output.writeLE(UInt16(0))
            try output.writeLE(UInt16(0))
            try output.writeLE(UInt32(0))
            try output.writeLE(entry.localHeaderOffset)
            try output.write(contentsOf: entry.nameData)
        }
        guard output.offsetInFile <= UInt64(UInt32.max) else { throw ZIPError.archiveTooLarge }
        let centralSize = UInt32(output.offsetInFile) - centralOffset
        let entryCount = UInt16(centralEntries.count)
        try output.writeLE(UInt32(0x06054b50))
        try output.writeLE(UInt16(0))
        try output.writeLE(UInt16(0))
        try output.writeLE(entryCount)
        try output.writeLE(entryCount)
        try output.writeLE(centralSize)
        try output.writeLE(centralOffset)
        try output.writeLE(UInt16(0))
        try output.synchronize()
    }

    private static func dosDateTime(_ date: Date) -> (time: UInt16, date: UInt16) {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(1980, components.year ?? 1980)
        let month = max(1, components.month ?? 1)
        let day = max(1, components.day ?? 1)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let second = components.second ?? 0
        let dosTime = UInt16((hour << 11) | (minute << 5) | (second / 2))
        let dosDate = UInt16(((year - 1980) << 9) | (month << 5) | day)
        return (dosTime, dosDate)
    }
}

private struct CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) == 1
                ? 0xedb88320 ^ (value >> 1)
                : value >> 1
        }
        return value
    }

    private var value: UInt32 = 0xffffffff

    mutating func update(_ data: Data) {
        for byte in data {
            let index = Int((value ^ UInt32(byte)) & 0xff)
            value = Self.table[index] ^ (value >> 8)
        }
    }

    func finalize() -> UInt32 {
        value ^ 0xffffffff
    }
}

private extension FileHandle {
    func writeLE<T: FixedWidthInteger>(_ value: T) throws {
        var littleEndian = value.littleEndian
        let data = withUnsafeBytes(of: &littleEndian) { Data($0) }
        try write(contentsOf: data)
    }
}

private enum ZIPError: LocalizedError {
    case archiveTooLarge
    case invalidFileName

    var errorDescription: String? {
        switch self {
        case .archiveTooLarge:
            "Das Beweispaket ist größer als 4 GB. Bitte exportiere einen kürzeren Zeitraum oder weniger Videos."
        case .invalidFileName:
            "Ein Dateiname ist für das Beweispaket zu lang."
        }
    }
}
