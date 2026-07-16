import Foundation
import HVMeldeCore

enum TechnicalReportExporter {
    static func exportJSON(
        report: IncidentReport,
        profile: UserProfile,
        property: ManagedProperty,
        management: PropertyManagement?,
        evidencePhotos: [EvidencePhoto]
    ) throws -> URL {
        let document = TechnicalReportDocument(
            schemaVersion: 2,
            exportedAt: Date(),
            report: report,
            profile: profile,
            property: property,
            management: management,
            evidencePhotos: evidencePhotos.map(TechnicalEvidencePhoto.init)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Technische-Daten-\(report.id.uuidString).json")
        try encoder.encode(document).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}

private struct TechnicalReportDocument: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let report: IncidentReport
    let profile: UserProfile
    let property: ManagedProperty
    let management: PropertyManagement?
    let evidencePhotos: [TechnicalEvidencePhoto]
}

private struct TechnicalEvidencePhoto: Codable {
    let id: UUID
    let fileName: String
    let sha256: String
    let importedAt: Date
    let source: EvidencePhotoSource
    let imageTimestamp: EvidenceImageTimestamp
    let confirmedAnalysis: ConfirmedImageAnalysis?

    init(_ photo: EvidencePhoto) {
        id = photo.id
        fileName = photo.localURL.lastPathComponent
        sha256 = photo.sha256
        importedAt = photo.importedAt
        source = photo.source
        imageTimestamp = photo.imageTimestamp
        confirmedAnalysis = photo.confirmedAnalysis
    }
}
