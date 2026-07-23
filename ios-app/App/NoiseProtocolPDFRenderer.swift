import AVFoundation
import HVMeldeCore
import UIKit

@MainActor
enum NoiseProtocolPDFRenderer {
    static func render(
        noiseProtocol: NoiseProtocol,
        profile: UserProfile,
        management: PropertyManagement?,
        evidenceURL: (NoiseEvidenceFile) -> URL?
    ) throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Laermprotokoll-\(noiseProtocol.id.uuidString).pdf")
        let pageBounds = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let index = NoiseProtocolEvidenceIndex(noiseProtocol: noiseProtocol)

        try renderer.writePDF(to: outputURL) { context in
            var writer = Writer(context: context, bounds: pageBounds, protocolID: noiseProtocol.id)
            writer.beginPage()
            writer.text(profile.fullName, font: .systemFont(ofSize: 9, weight: .semibold))
            writer.text(profile.address.formatted, font: .systemFont(ofSize: 9))
            if !profile.email.isEmpty { writer.text(profile.email, font: .systemFont(ofSize: 9)) }
            if !profile.phone.isEmpty { writer.text(profile.phone, font: .systemFont(ofSize: 9)) }
            writer.space(20)

            if let management {
                writer.text(management.name, font: .systemFont(ofSize: 11, weight: .semibold))
                writer.text(management.address.formatted, font: .systemFont(ofSize: 10))
            } else {
                writer.text("An die zuständige Hausverwaltung", font: .systemFont(ofSize: 11, weight: .semibold))
            }
            writer.space(18)
            writer.text(
                Date().formatted(date: .long, time: .omitted),
                font: .systemFont(ofSize: 10),
                alignment: .right
            )
            writer.space(18)
            writer.text(
                "\(noiseProtocol.recipientPropertyName) – Lärmprotokoll – \(periodText(noiseProtocol))",
                font: .systemFont(ofSize: 14, weight: .bold)
            )
            writer.space(16)
            writer.paragraph("Sehr geehrte Damen und Herren,")
            writer.paragraph(
                "hiermit übermittle ich Ihnen ein fortlaufendes Lärmprotokoll zum Objekt "
                    + "\(noiseProtocol.recipientPropertyName), \(noiseProtocol.propertyAddress.formatted). "
                    + "Die Dokumentation umfasst \(noiseProtocol.disturbanceCount) Ruhestörungen"
                    + interventionSuffix(noiseProtocol)
                    + " im Zeitraum \(periodText(noiseProtocol))."
            )
            if !noiseProtocol.suspectedSource.isEmpty {
                writer.paragraph(
                    "Als mögliche Lärmquelle wurde wahrgenommen: \(noiseProtocol.suspectedSource). "
                        + "Diese Angabe stellt keine abschließende Feststellung der Verursachung dar."
                )
            }
            writer.paragraph(
                noiseProtocol.requestsManagementResponse
                    ? "Ich ersuche um Prüfung des Sachverhalts und um Rückmeldung zu den veranlassten Maßnahmen."
                    : "Ich übermittle diese Dokumentation zu Ihrer Information und weiteren Veranlassung."
            )
            writer.paragraph(
                noiseProtocol.allowsNameDisclosure
                    ? "Mein Name darf dem mutmaßlichen Verursacher im Rahmen der Bearbeitung mitgeteilt werden."
                    : "Ich ersuche darum, meinen Namen gegenüber dem mutmaßlichen Verursacher nicht offenzulegen."
            )
            if index.evidence.isEmpty {
                writer.paragraph("Zu diesem Protokoll wurden keine digitalen Beweisdateien beigefügt.")
            } else {
                writer.paragraph(
                    "Die im Anlagenverzeichnis aufgeführten Dateien sind Bestandteil dieser Dokumentation. "
                        + "Die angegebenen SHA-256-Prüfsummen ermöglichen die Prüfung, ob die übermittelten "
                        + "Dateien seit Erstellung des Beweispakets unverändert geblieben sind."
                )
            }
            writer.space(14)
            writer.paragraph("Mit freundlichen Grüßen")
            writer.space(20)
            writer.text(profile.fullName, font: .systemFont(ofSize: 11, weight: .semibold))

            writer.pageBreak()
            writer.heading("Zusammenfassung")
            writer.keyValue("Protokoll-ID", noiseProtocol.id.uuidString)
            writer.keyValue("Objekt", noiseProtocol.recipientPropertyName)
            writer.keyValue("Anschrift", noiseProtocol.propertyAddress.formatted)
            writer.keyValue("Zeitraum", periodText(noiseProtocol))
            writer.keyValue("Ruhestörungen", "\(noiseProtocol.disturbanceCount)")
            writer.keyValue("Einsätze/Maßnahmen", "\(noiseProtocol.interventionCount)")
            writer.keyValue("Beweisdateien", "\(noiseProtocol.evidenceFileCount)")
            writer.keyValue("Status", noiseProtocol.status.rawValue)

            writer.space(18)
            writer.heading("Chronologisches Protokoll")
            for indexedEntry in index.entries {
                let entry = indexedEntry.entry
                writer.ensureSpace(105)
                writer.text(
                    "\(indexedEntry.number) · \(entry.kind.rawValue)",
                    font: .systemFont(ofSize: 11, weight: .bold)
                )
                writer.keyValue("Zeit", eventTimeText(entry))
                if entry.kind == .disturbance {
                    if !entry.noiseType.isEmpty { writer.keyValue("Art", entry.noiseType) }
                    if !entry.sourceLocation.isEmpty { writer.keyValue("Wahrgenommene Quelle", entry.sourceLocation) }
                    if !entry.perceivedLocation.isEmpty { writer.keyValue("Wahrgenommen in", entry.perceivedLocation) }
                    if !entry.impact.isEmpty { writer.keyValue("Auswirkung", entry.impact) }
                    if !entry.witnesses.isEmpty { writer.keyValue("Zeugen", entry.witnesses) }
                } else {
                    if !entry.responderType.isEmpty { writer.keyValue("Einsatzkräfte", entry.responderType) }
                    if !entry.stationOrUnit.isEmpty { writer.keyValue("Dienststelle/Einheit", entry.stationOrUnit) }
                    if !entry.officers.isEmpty { writer.keyValue("Einschreitende Personen", entry.officers) }
                    if !entry.referenceNumber.isEmpty { writer.keyValue("Einsatz-/Aktennummer", entry.referenceNumber) }
                    if !entry.outcome.isEmpty { writer.keyValue("Ergebnis", entry.outcome) }
                }
                if !entry.details.isEmpty { writer.keyValue("Beschreibung", entry.details) }
                if !entry.evidenceFiles.isEmpty {
                    writer.keyValue(
                        "Beweismittel",
                        index.evidence.filter { $0.entry.id == entry.id }.map(\.attachmentNumber).joined(separator: ", ")
                    )
                }
                writer.rule()
            }

            if !index.evidence.isEmpty {
                writer.pageBreak()
                writer.heading("Anlagen- und Beweismittelverzeichnis")
                writer.paragraph(
                    "Alle Hashwerte beziehen sich auf die unveränderten Dateiinhalte der im Beweispaket "
                        + "enthaltenen Originaldateien."
                )
                for item in index.evidence {
                    writer.ensureSpace(105)
                    writer.text(
                        "\(item.attachmentNumber) · \(item.entryNumber)",
                        font: .systemFont(ofSize: 11, weight: .bold)
                    )
                    writer.keyValue("Zuordnung", item.entrySummary)
                    writer.keyValue("Datei", item.exportFileName)
                    writer.keyValue("Originalname", item.evidence.originalFileName)
                    if let capturedAt = item.evidence.capturedAt {
                        writer.keyValue(
                            "Aufnahmezeit",
                            capturedAt.formatted(date: .numeric, time: .standard)
                        )
                    }
                    if let duration = item.evidence.durationSeconds {
                        writer.keyValue("Videodauer", durationText(duration))
                    }
                    writer.keyValue(
                        "Dateigröße",
                        ByteCountFormatter.string(fromByteCount: item.evidence.byteCount, countStyle: .file)
                    )
                    writer.text("SHA-256", font: .systemFont(ofSize: 8, weight: .semibold))
                    writer.text(
                        item.evidence.sha256,
                        font: .monospacedSystemFont(ofSize: 7.5, weight: .regular)
                    )
                    writer.rule()
                }

                for item in index.evidence where item.evidence.kind == .video {
                    guard let url = evidenceURL(item.evidence),
                          let image = thumbnail(for: url) else { continue }
                    writer.pageBreak()
                    writer.heading("\(item.attachmentNumber) · Videovorschau")
                    writer.keyValue("Datei", item.exportFileName)
                    writer.keyValue("Zuordnung", "\(item.entryNumber) – \(item.entrySummary)")
                    let maxWidth = writer.contentWidth
                    let maxHeight: CGFloat = 480
                    let scale = min(maxWidth / image.size.width, maxHeight / image.size.height)
                    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    writer.image(image, size: size)
                    writer.space(10)
                    writer.paragraph(
                        "Diese Vorschau dient nur der Zuordnung. Maßgeblich ist die im Beweispaket "
                            + "enthaltene Originalvideodatei mit der im Anlagenverzeichnis angegebenen Prüfsumme."
                    )
                }
            }
        }
        return outputURL
    }

    private static func interventionSuffix(_ noiseProtocol: NoiseProtocol) -> String {
        noiseProtocol.interventionCount == 0
            ? ""
            : " und \(noiseProtocol.interventionCount) Einsätze beziehungsweise Maßnahmen"
    }

    private static func periodText(_ noiseProtocol: NoiseProtocol) -> String {
        guard let first = noiseProtocol.firstEventAt else { return "noch ohne Einträge" }
        let last = noiseProtocol.lastEventAt ?? first
        return "\(first.formatted(date: .numeric, time: .omitted)) bis \(last.formatted(date: .numeric, time: .omitted))"
    }

    private static func eventTimeText(_ entry: NoiseTimelineEntry) -> String {
        let start = entry.startedAt.formatted(date: .numeric, time: .shortened)
        guard let endedAt = entry.endedAt else { return "\(start), Ende noch offen" }
        return "\(start) bis \(endedAt.formatted(date: .numeric, time: .shortened))"
    }

    private static func durationText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private static func thumbnail(for url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1200, height: 1200)
        guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct NoiseProtocolEvidenceIndex {
    struct IndexedEntry {
        let entry: NoiseTimelineEntry
        let number: String
    }

    struct IndexedEvidence {
        let evidence: NoiseEvidenceFile
        let entry: NoiseTimelineEntry
        let entryNumber: String
        let attachmentNumber: String
        let exportFileName: String
        let entrySummary: String
    }

    let entries: [IndexedEntry]
    let evidence: [IndexedEvidence]

    init(noiseProtocol: NoiseProtocol) {
        let orderedEntries = noiseProtocol.entries.sorted { $0.startedAt < $1.startedAt }
        var disturbanceIndex = 0
        var interventionIndex = 0
        var indexedEntries: [IndexedEntry] = []
        var indexedEvidence: [IndexedEvidence] = []
        var attachmentIndex = 0

        for entry in orderedEntries {
            let number: String
            switch entry.kind {
            case .disturbance:
                disturbanceIndex += 1
                number = "L-\(String(format: "%03d", disturbanceIndex))"
            case .intervention:
                interventionIndex += 1
                number = "E-\(String(format: "%03d", interventionIndex))"
            }
            indexedEntries.append(IndexedEntry(entry: entry, number: number))

            for (fileIndex, file) in entry.evidenceFiles.enumerated() {
                attachmentIndex += 1
                let ext = URL(fileURLWithPath: file.storedFileName).pathExtension.lowercased()
                let type = file.kind == .video ? "Video" : (file.kind == .photo ? "Foto" : "Dokument")
                let name = "\(number)_\(type)-\(String(format: "%02d", fileIndex + 1)).\(ext)"
                let summary = entry.kind == .disturbance
                    ? (entry.noiseType.isEmpty ? "Ruhestörung" : entry.noiseType)
                    : (entry.responderType.isEmpty ? "Einsatz oder Maßnahme" : entry.responderType)
                indexedEvidence.append(IndexedEvidence(
                    evidence: file,
                    entry: entry,
                    entryNumber: number,
                    attachmentNumber: "A-\(String(format: "%03d", attachmentIndex))",
                    exportFileName: name,
                    entrySummary: summary
                ))
            }
        }
        entries = indexedEntries
        evidence = indexedEvidence
    }
}

private struct Writer {
    let context: UIGraphicsPDFRendererContext
    let bounds: CGRect
    let protocolID: UUID
    private(set) var page = 0
    private(set) var y: CGFloat = 0
    let margin: CGFloat = 46
    let bottomMargin: CGFloat = 48

    var contentWidth: CGFloat { bounds.width - 2 * margin }

    mutating func beginPage() {
        context.beginPage()
        page += 1
        y = margin
        let footer = "Lärmprotokoll \(protocolID.uuidString) · Seite \(page)"
        (footer as NSString).draw(
            in: CGRect(x: margin, y: bounds.height - 30, width: contentWidth, height: 14),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 7),
                .foregroundColor: UIColor.darkGray
            ]
        )
    }

    mutating func pageBreak() {
        beginPage()
    }

    mutating func ensureSpace(_ height: CGFloat) {
        if y + height > bounds.height - bottomMargin {
            pageBreak()
        }
    }

    mutating func heading(_ value: String) {
        ensureSpace(36)
        text(value, font: .systemFont(ofSize: 16, weight: .bold))
        space(9)
    }

    mutating func paragraph(_ value: String) {
        text(value, font: .systemFont(ofSize: 10.5), lineSpacing: 3)
        space(9)
    }

    mutating func keyValue(_ key: String, _ value: String) {
        guard !value.isEmpty else { return }
        let keyWidth: CGFloat = 125
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9.5),
            .foregroundColor: UIColor.black
        ]
        let valueRect = (value as NSString).boundingRect(
            with: CGSize(width: contentWidth - keyWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        let height = max(16, ceil(valueRect.height) + 3)
        ensureSpace(height)
        (key as NSString).draw(
            in: CGRect(x: margin, y: y, width: keyWidth - 8, height: height),
            withAttributes: [.font: UIFont.systemFont(ofSize: 9.5, weight: .semibold)]
        )
        (value as NSString).draw(
            in: CGRect(x: margin + keyWidth, y: y, width: contentWidth - keyWidth, height: height),
            withAttributes: attributes
        )
        y += height
    }

    mutating func text(
        _ value: String,
        font: UIFont,
        alignment: NSTextAlignment = .left,
        lineSpacing: CGFloat = 1
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineSpacing = lineSpacing
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black,
            .paragraphStyle: style
        ]
        let rect = (value as NSString).boundingRect(
            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        let height = ceil(rect.height) + 2
        ensureSpace(height)
        (value as NSString).draw(
            in: CGRect(x: margin, y: y, width: contentWidth, height: height),
            withAttributes: attributes
        )
        y += height
    }

    mutating func image(_ image: UIImage, size: CGSize) {
        ensureSpace(size.height)
        image.draw(in: CGRect(x: margin, y: y, width: size.width, height: size.height))
        y += size.height
    }

    mutating func rule() {
        ensureSpace(12)
        y += 5
        context.cgContext.setStrokeColor(UIColor.lightGray.cgColor)
        context.cgContext.setLineWidth(0.5)
        context.cgContext.move(to: CGPoint(x: margin, y: y))
        context.cgContext.addLine(to: CGPoint(x: bounds.width - margin, y: y))
        context.cgContext.strokePath()
        y += 7
    }

    mutating func space(_ value: CGFloat) {
        ensureSpace(value)
        y += value
    }
}
