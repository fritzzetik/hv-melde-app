import HVMeldeCore
import UIKit

@MainActor
enum PDFReportRenderer {
    static func render(
        _ report: IncidentReport,
        profile: UserProfile,
        property: ManagedProperty,
        management: PropertyManagement?,
        evidencePhoto: EvidencePhoto?
    ) throws -> URL {
        let pageBounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let data = renderer.pdfData { context in
            context.beginPage()
            draw(report, profile: profile, property: property, management: management, in: pageBounds)
            if let evidencePhoto {
                context.beginPage()
                drawEvidencePhoto(evidencePhoto, in: pageBounds)
                if let analysis = evidencePhoto.confirmedAnalysis {
                    context.beginPage()
                    drawConfirmedAnalysis(analysis, in: pageBounds)
                }
            }
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Meldung-\(report.id.uuidString).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func drawEvidencePhoto(_ photo: EvidencePhoto, in bounds: CGRect) {
        let margin: CGFloat = 48
        let contentWidth = bounds.width - (2 * margin)
        var y = margin

        y = drawText(
            "Beweisfoto und technische Angaben",
            at: y,
            width: contentWidth,
            font: .boldSystemFont(ofSize: 20),
            color: .label,
            margin: margin
        ) + 14

        if let image = UIImage(data: photo.data) {
            let maximumImageSize = CGSize(width: contentWidth, height: 430)
            let scale = min(
                maximumImageSize.width / image.size.width,
                maximumImageSize.height / image.size.height
            )
            let imageSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let imageRect = CGRect(
                x: margin + (contentWidth - imageSize.width) / 2,
                y: y,
                width: imageSize.width,
                height: imageSize.height
            )
            image.draw(in: imageRect)
            y = imageRect.maxY + 14
        } else {
            y = drawText(
                "Das gespeicherte Originalbild konnte nicht dargestellt werden.",
                at: y,
                width: contentWidth,
                font: .systemFont(ofSize: 11),
                color: .systemRed,
                margin: margin
            ) + 12
        }

        let captureValue: String
        if let capturedAt = photo.imageTimestamp.capturedAt {
            captureValue = dateFormatter.string(from: capturedAt)
        } else {
            captureValue = "Nicht in den Bildmetadaten vorhanden"
        }

        let timeZoneValue: String
        if photo.imageTimestamp.timeZoneWasEmbedded {
            timeZoneValue = "Im Bild enthalten bzw. bei direkter Kameraaufnahme durch die Geräteuhr bestimmt (\(photo.imageTimestamp.interpretedTimeZone ?? "unbekannt"))"
        } else if let interpretedTimeZone = photo.imageTimestamp.interpretedTimeZone {
            timeZoneValue = "Nicht im Bild enthalten; als \(interpretedTimeZone) interpretiert"
        } else {
            timeZoneValue = "Nicht verfügbar"
        }

        let hashForDisplay = photo.sha256.chunked(every: 32).joined(separator: " ")
        var rows: [(String, String)] = [
            ("Fotoquelle", photo.source.rawValue),
            ("Aufnahmezeit des Bildes", captureValue),
            ("Zeitquelle", photo.imageTimestamp.source.rawValue),
            ("Zeitzonenangabe", timeZoneValue),
            ("Originaler Metadatenwert", photo.imageTimestamp.rawValue ?? "Nicht verfügbar"),
            ("In die App übernommen", dateFormatter.string(from: photo.importedAt)),
            ("SHA-256 des Originalbilds", hashForDisplay)
        ]

        if photo.confirmedAnalysis == nil {
            rows.append(("Lokale Bilderkennung", "Noch nicht durch die Nutzerin oder den Nutzer bestätigt"))
        }

        for (label, value) in rows where !value.isEmpty {
            y = drawText(
                label.uppercased(),
                at: y,
                width: contentWidth,
                font: .boldSystemFont(ofSize: 8),
                color: .secondaryLabel,
                margin: margin
            ) + 2
            y = drawText(
                value,
                at: y,
                width: contentWidth,
                font: label.contains("SHA-256") ? .monospacedSystemFont(ofSize: 9, weight: .regular) : .systemFont(ofSize: 10),
                color: .label,
                margin: margin
            ) + 7
        }
    }

    private static func drawConfirmedAnalysis(
        _ analysis: ConfirmedImageAnalysis,
        in bounds: CGRect
    ) {
        let margin: CGFloat = 48
        let contentWidth = bounds.width - (2 * margin)
        var y = margin

        y = drawText(
            "Bestätigte lokale Bildauswertung",
            at: y,
            width: contentWidth,
            font: .boldSystemFont(ofSize: 20),
            color: .label,
            margin: margin
        ) + 18

        var rows: [(String, String)] = [
            ("Meldekategorie", analysis.category.rawValue),
            ("Fahrzeug erkannt", analysis.vehicleDetected ? "Ja (Konfidenz \(percentFormatter.string(from: NSNumber(value: analysis.vehicleConfidence)) ?? "–"))" : "Nein bzw. unsicher"),
            ("Bestätigtes Kennzeichen", analysis.confirmedLicensePlate),
            ("Bestätigte Fahrzeugbeschreibung", analysis.confirmedVehicleDescription),
            ("Bestätigte Szenenbeschreibung", analysis.confirmedSceneSummary),
            ("Analyse bestätigt", dateFormatter.string(from: analysis.analyzedAt)),
            ("Analyseverfahren", analysis.analyzerDescription)
        ]

        if let type = analysis.suggestedVehicleType {
            rows.insert(
                ("Automatisch vorgeschlagener Fahrzeugtyp", suggestionValue(type, confidence: analysis.suggestedVehicleTypeConfidence)),
                at: 2
            )
        }
        if let color = analysis.suggestedVehicleColor {
            rows.insert(
                ("Heuristisch geschätzte Fahrzeugfarbe", suggestionValue(color, confidence: analysis.suggestedVehicleColorConfidence)),
                at: min(3, rows.count)
            )
        }
        if !analysis.suggestedSceneObjects.isEmpty {
            let values = analysis.suggestedSceneObjects.map {
                suggestionValue($0.name, confidence: $0.confidence)
            }
            rows.insert(("Automatisch vorgeschlagene Nebenobjekte", values.joined(separator: ", ")), at: min(4, rows.count))
        }

        for (label, value) in rows where !value.isEmpty {
            y = drawText(
                label.uppercased(),
                at: y,
                width: contentWidth,
                font: .boldSystemFont(ofSize: 9),
                color: .secondaryLabel,
                margin: margin
            ) + 3
            y = drawText(
                value,
                at: y,
                width: contentWidth,
                font: .systemFont(ofSize: 12),
                color: .label,
                margin: margin
            ) + 13
        }

        _ = drawText(
            "Diese Angaben wurden lokal vorgeschlagen und anschließend in der App bestätigt. Die Konfidenz ist ein technischer Hinweis und keine Tatsachenfeststellung.",
            at: y + 18,
            width: contentWidth,
            font: .systemFont(ofSize: 9),
            color: .secondaryLabel,
            margin: margin
        )
    }

    private static func draw(
        _ report: IncidentReport,
        profile: UserProfile,
        property: ManagedProperty,
        management: PropertyManagement?,
        in bounds: CGRect
    ) {
        let margin: CGFloat = 48
        let contentWidth = bounds.width - (2 * margin)
        var y = margin

        y = drawText(
            "Dokumentation eines Garagenvorfalls",
            at: y,
            width: contentWidth,
            font: .boldSystemFont(ofSize: 20),
            color: .label,
            margin: margin
        ) + 18

        let rows: [(String, String)] = [
            ("Meldungs-ID", report.id.uuidString),
            ("Erstellt", dateFormatter.string(from: report.createdAt)),
            ("Beobachtet", dateFormatter.string(from: report.incidentAt)),
            ("Absender", profile.fullName),
            ("Anschrift Absender", profile.address.formatted),
            ("Kontakt Absender", [profile.phone, profile.email].filter { !$0.isEmpty }.joined(separator: " · ")),
            ("Objekt", property.displayName),
            ("Objektanschrift", property.address.formatted),
            ("Nutzungsverhältnis", property.occupancyRole.rawValue),
            ("Hausverwaltung", management?.name ?? ""),
            ("Melde-E-Mail", property.reportEmail),
            ("Garagenbereich", report.garageLocation),
            ("Kennzeichen", report.licensePlate),
            ("Fahrzeug", report.vehicleDescription),
            ("Verstoß", report.violation),
            ("Beschreibung", report.notes),
            ("Zeugen", report.witnesses)
        ]

        for (label, value) in rows where !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            y = drawText(
                label.uppercased(),
                at: y,
                width: contentWidth,
                font: .boldSystemFont(ofSize: 9),
                color: .secondaryLabel,
                margin: margin
            ) + 3
            y = drawText(
                value,
                at: y,
                width: contentWidth,
                font: .systemFont(ofSize: 12),
                color: .label,
                margin: margin
            ) + 13
        }

        _ = drawText(
            "Hinweis: Dieses Dokument wurde lokal auf dem Gerät erstellt. Zeitangaben beruhen auf der Geräteuhr. Es wurde kein externer Zeitstempel verwendet.",
            at: min(y + 12, bounds.height - 100),
            width: contentWidth,
            font: .systemFont(ofSize: 9),
            color: .secondaryLabel,
            margin: margin
        )
    }

    @discardableResult
    private static func drawText(
        _ text: String,
        at y: CGFloat,
        width: CGFloat,
        font: UIFont,
        color: UIColor,
        margin: CGFloat
    ) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let constraint = CGSize(width: width, height: .greatestFiniteMagnitude)
        let size = (text as NSString).boundingRect(
            with: constraint,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        ).integral.size
        (text as NSString).draw(
            in: CGRect(x: margin, y: y, width: width, height: size.height),
            withAttributes: attributes
        )
        return y + size.height
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_AT")
        formatter.dateStyle = .long
        formatter.timeStyle = .medium
        formatter.timeZone = .autoupdatingCurrent
        return formatter
    }()

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static func suggestionValue(_ value: String, confidence: Float?) -> String {
        guard let confidence,
              let formatted = percentFormatter.string(from: NSNumber(value: confidence)) else {
            return value
        }
        return "\(value) (Konfidenz \(formatted))"
    }
}

private extension String {
    func chunked(every length: Int) -> [String] {
        guard length > 0 else { return [self] }
        return stride(from: 0, to: count, by: length).map { offset in
            let start = index(startIndex, offsetBy: offset)
            let end = index(start, offsetBy: min(length, count - offset))
            return String(self[start..<end])
        }
    }
}
