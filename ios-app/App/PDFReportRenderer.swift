import HVMeldeCore
import UIKit

@MainActor
enum PDFReportRenderer {
    static func render(
        _ report: IncidentReport,
        profile: UserProfile,
        property: ManagedProperty,
        management: PropertyManagement?,
        evidencePhotos: [EvidencePhoto]
    ) throws -> URL {
        let pageBounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let analysisCount = evidencePhotos.filter { $0.confirmedAnalysis != nil }.count
        let totalPages = 2 + evidencePhotos.count + analysisCount
        let attachmentTitles = attachmentSummary(for: evidencePhotos)
        let data = renderer.pdfData { context in
            var pageNumber = 1
            context.beginPage()
            drawLetter(
                report,
                profile: profile,
                property: property,
                management: management,
                attachmentTitles: attachmentTitles,
                in: pageBounds
            )
            drawFooter(report: report, page: pageNumber, totalPages: totalPages, in: pageBounds)

            pageNumber += 1
            context.beginPage()
            drawCaseDetails(report, profile: profile, property: property, management: management, in: pageBounds)
            drawFooter(report: report, page: pageNumber, totalPages: totalPages, in: pageBounds)

            var attachmentNumber = 2
            for evidencePhoto in evidencePhotos {
                pageNumber += 1
                context.beginPage()
                drawEvidencePhoto(evidencePhoto, attachmentNumber: attachmentNumber, in: pageBounds)
                drawFooter(report: report, page: pageNumber, totalPages: totalPages, in: pageBounds)
                attachmentNumber += 1
                if let analysis = evidencePhoto.confirmedAnalysis {
                    pageNumber += 1
                    context.beginPage()
                    drawConfirmedAnalysis(analysis, attachmentNumber: attachmentNumber, in: pageBounds)
                    drawFooter(report: report, page: pageNumber, totalPages: totalPages, in: pageBounds)
                    attachmentNumber += 1
                }
            }
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Meldung-\(report.id.uuidString).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func drawEvidencePhoto(
        _ photo: EvidencePhoto,
        attachmentNumber: Int,
        in bounds: CGRect
    ) {
        let margin: CGFloat = 48
        let contentWidth = bounds.width - (2 * margin)
        var y = margin

        y = drawText(
            "Anlage \(attachmentNumber) - Beweisfoto und technische Angaben",
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
        attachmentNumber: Int,
        in bounds: CGRect
    ) {
        let margin: CGFloat = 48
        let contentWidth = bounds.width - (2 * margin)
        var y = margin

        y = drawText(
            "Anlage \(attachmentNumber) - Bestätigte lokale Bildauswertung",
            at: y,
            width: contentWidth,
            font: .boldSystemFont(ofSize: 20),
            color: .label,
            margin: margin
        ) + 18

        var rows: [(String, String)] = [("Meldekategorie", analysis.category.rawValue)]

        if analysis.category.expectsVehicle {
            rows.append((
                "Fahrzeug erkannt",
                analysis.vehicleDetected
                    ? "Ja (Konfidenz \(percentFormatter.string(from: NSNumber(value: analysis.vehicleConfidence)) ?? "-"))"
                    : "Nein bzw. unsicher"
            ))
            if let type = analysis.suggestedVehicleType {
                rows.append((
                    "Automatisch vorgeschlagener Fahrzeugtyp",
                    suggestionValue(type, confidence: analysis.suggestedVehicleTypeConfidence)
                ))
            }
            if let color = analysis.suggestedVehicleColor {
                rows.append((
                    "Heuristisch geschätzte Fahrzeugfarbe",
                    suggestionValue(color, confidence: analysis.suggestedVehicleColorConfidence)
                ))
            }
        }
        if !analysis.suggestedSceneObjects.isEmpty {
            let values = analysis.suggestedSceneObjects.map {
                suggestionValue($0.name, confidence: $0.confidence)
            }
            rows.append(("Automatisch vorgeschlagene Objekte", values.joined(separator: ", ")))
        }
        if analysis.category.expectsVehicle {
            rows.append(("Bestätigtes Kennzeichen", analysis.confirmedLicensePlate))
            rows.append(("Bestätigte Fahrzeugbeschreibung", analysis.confirmedVehicleDescription))
        }
        rows.append(("Bestätigte Szenenbeschreibung", analysis.confirmedSceneSummary))
        rows.append(("Analyse bestätigt", dateFormatter.string(from: analysis.analyzedAt)))
        rows.append(("Analyseverfahren", analysis.analyzerDescription))

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

    private static func drawLetter(
        _ report: IncidentReport,
        profile: UserProfile,
        property: ManagedProperty,
        management: PropertyManagement?,
        attachmentTitles: [String],
        in bounds: CGRect
    ) {
        let margin: CGFloat = 50
        let contentWidth = bounds.width - (2 * margin)
        var y: CGFloat = 34

        let senderLine = [
            profile.fullName,
            profile.address.formatted,
            profile.email,
            profile.phone
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: " · ")
        _ = drawText(
            senderLine,
            at: y,
            width: contentWidth - 150,
            font: .systemFont(ofSize: 7.5),
            color: .secondaryLabel,
            margin: margin
        )
        drawRightAlignedText(
            "MELDUNG / DOKUMENTATION",
            at: y,
            font: .boldSystemFont(ofSize: 8),
            color: accentColor,
            rightMargin: margin,
            in: bounds
        )
        drawLine(at: 54, margin: margin, width: contentWidth, color: accentColor)

        let recipientName = management?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var recipientLines = [
            recipientName?.isEmpty == false ? recipientName! : "An die zuständige Hausverwaltung"
        ]
        if let management, !management.address.formatted.isEmpty {
            recipientLines.append(postalAddressLines(management.address))
        } else if !property.reportEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recipientLines.append("per E-Mail: \(property.reportEmail)")
        }

        y = 78
        y = drawText(
            recipientLines.joined(separator: "\n"),
            at: y,
            width: 290,
            font: .systemFont(ofSize: 10.5),
            color: .label,
            margin: margin
        )

        drawRightAlignedText(
            letterDateFormatter.string(from: report.createdAt),
            at: max(154, y + 12),
            font: .systemFont(ofSize: 10.5),
            color: .label,
            rightMargin: margin,
            in: bounds
        )
        y = max(198, y + 52)

        y = drawText(
            reportSubject(report, property: property),
            at: y,
            width: contentWidth,
            font: .boldSystemFont(ofSize: 15),
            color: .label,
            margin: margin
        ) + 23

        y = drawText(
            "Sehr geehrte Damen und Herren,",
            at: y,
            width: contentWidth,
            font: .systemFont(ofSize: 11.5),
            color: .label,
            margin: margin
        ) + 15

        let scopePhrase: String
        if report.isCommonArea {
            scopePhrase = "auf einer Allgemeinfläche des unten genannten Objekts"
        } else if property.occupancyRole == .tenant {
            scopePhrase = "in meinem gemieteten Objekt"
        } else {
            scopePhrase = "in meinem Eigentumsobjekt"
        }
        y = drawText(
            "hiermit informiere ich Sie über einen dokumentierten Vorfall \(scopePhrase). Ich ersuche um Prüfung und gegebenenfalls um die erforderlichen Maßnahmen.",
            at: y,
            width: contentWidth,
            font: .systemFont(ofSize: 11.5),
            color: .label,
            margin: margin
        ) + 16

        var factLines = [
            "Objekt: \(property.officialDisplayName)",
            "Objekttyp: \(property.propertyType.rawValue)",
            "Objektanschrift: \(property.address.formatted)",
            "Beobachtet: \(dateFormatter.string(from: report.incidentAt))",
            "Bereich: \(report.garageLocation)",
            "Meldegrund: \(report.violation)"
        ]
        if !report.licensePlate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            factLines.append("Kennzeichen: \(report.licensePlate)")
        }
        let boxHeight = CGFloat(factLines.count) * 15 + 20
        let boxRect = CGRect(x: margin, y: y, width: contentWidth, height: boxHeight)
        UIColor.secondarySystemBackground.setFill()
        UIBezierPath(roundedRect: boxRect, cornerRadius: 8).fill()
        _ = drawText(
            factLines.joined(separator: "\n"),
            at: y + 10,
            width: contentWidth - 24,
            font: .systemFont(ofSize: 10.5),
            color: .label,
            margin: margin + 12
        )
        y = boxRect.maxY + 17

        let trimmedNotes = report.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            y = drawText(
                "Kurzbeschreibung",
                at: y,
                width: contentWidth,
                font: .boldSystemFont(ofSize: 9),
                color: .secondaryLabel,
                margin: margin
            ) + 4
            y = drawText(
                letterSummary(trimmedNotes),
                at: y,
                width: contentWidth,
                font: .systemFont(ofSize: 11),
                color: .label,
                margin: margin
            ) + 15
        }

        y = drawText(
            "Die vollständigen Falldaten und - soweit vorhanden - die Foto- und Analysedokumentation finden Sie in den beigefügten Anlagen.",
            at: y,
            width: contentWidth,
            font: .systemFont(ofSize: 11),
            color: .label,
            margin: margin
        ) + 18

        y = drawText(
            "Mit freundlichen Grüßen\n\n\(profile.fullName)",
            at: y,
            width: contentWidth,
            font: .systemFont(ofSize: 11),
            color: .label,
            margin: margin
        ) + 18

        _ = drawText(
            "Anlagen\n" + attachmentTitles.joined(separator: "\n"),
            at: y,
            width: contentWidth,
            font: .systemFont(ofSize: 9.5),
            color: .secondaryLabel,
            margin: margin
        )
    }

    private static func attachmentSummary(for photos: [EvidencePhoto]) -> [String] {
        var titles = ["1. Falldetails und Meldungsdaten"]
        guard !photos.isEmpty else { return titles }
        let analysisCount = photos.filter { $0.confirmedAnalysis != nil }.count
        let lastNumber = 1 + photos.count + analysisCount
        var description = "\(photos.count) Beweisfoto"
        if photos.count != 1 { description += "s" }
        description += " mit technischen Angaben"
        if analysisCount > 0 {
            description += " und \(analysisCount) bestätigte Bildauswertung"
            if analysisCount != 1 { description += "en" }
        }
        titles.append("2–\(lastNumber). \(description)")
        return titles
    }

    private static func drawCaseDetails(
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
            "Anlage 1 - Falldetails und Meldungsdaten",
            at: y,
            width: contentWidth,
            font: .boldSystemFont(ofSize: 20),
            color: .label,
            margin: margin
        ) + 9

        y = drawText(
            "Strukturierte Zusammenfassung der in der App bestätigten Angaben.",
            at: y,
            width: contentWidth,
            font: .systemFont(ofSize: 9),
            color: .secondaryLabel,
            margin: margin
        ) + 16

        let rows: [(String, String)] = [
            ("Meldungs-ID", report.id.uuidString),
            ("Erstellt", dateFormatter.string(from: report.createdAt)),
            ("Beobachtet", dateFormatter.string(from: report.incidentAt)),
            ("Absender", profile.fullName),
            ("Anschrift Absender", profile.address.formatted),
            ("Kontakt Absender", [profile.phone, profile.email].filter { !$0.isEmpty }.joined(separator: " · ")),
            ("Offizielle Objektbezeichnung", property.officialDisplayName),
            ("Interner Objektname", property.officialDisplayName == property.displayName ? "" : property.displayName),
            ("Objekttyp", property.propertyType.rawValue),
            ("Objektanschrift", property.address.formatted),
            ("Nutzungsverhältnis", property.occupancyRole.rawValue),
            ("Bezug der Meldung", reportScope(for: report, property: property)),
            ("Hausverwaltung", management?.name ?? ""),
            ("Melde-E-Mail", property.reportEmail),
            ("Bereich / Ort", report.garageLocation),
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
                font: .boldSystemFont(ofSize: 8),
                color: .secondaryLabel,
                margin: margin
            ) + 2
            y = drawText(
                value,
                at: y,
                width: contentWidth,
                font: .systemFont(ofSize: 10.5),
                color: .label,
                margin: margin
            ) + 5
        }
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

    private static func drawFooter(
        report: IncidentReport,
        page: Int,
        totalPages: Int,
        in bounds: CGRect
    ) {
        let margin: CGFloat = 48
        let width = bounds.width - (2 * margin)
        drawLine(at: 786, margin: margin, width: width, color: .systemGray4)
        _ = drawText(
            "Lokal erstellt. Kein externer oder qualifizierter Zeitstempel.",
            at: 794,
            width: width - 120,
            font: .systemFont(ofSize: 7),
            color: .secondaryLabel,
            margin: margin
        )
        _ = drawText(
            "Meldungs-ID: \(report.id.uuidString)",
            at: 808,
            width: width - 90,
            font: .monospacedSystemFont(ofSize: 6.5, weight: .regular),
            color: .secondaryLabel,
            margin: margin
        )
        drawRightAlignedText(
            "Seite \(page) von \(totalPages)",
            at: 808,
            font: .systemFont(ofSize: 7),
            color: .secondaryLabel,
            rightMargin: margin,
            in: bounds
        )
    }

    private static func drawLine(
        at y: CGFloat,
        margin: CGFloat,
        width: CGFloat,
        color: UIColor
    ) {
        color.setStroke()
        let path = UIBezierPath()
        path.lineWidth = 0.7
        path.move(to: CGPoint(x: margin, y: y))
        path.addLine(to: CGPoint(x: margin + width, y: y))
        path.stroke()
    }

    private static func drawRightAlignedText(
        _ text: String,
        at y: CGFloat,
        font: UIFont,
        color: UIColor,
        rightMargin: CGFloat,
        in bounds: CGRect
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: CGPoint(x: bounds.maxX - rightMargin - size.width, y: y),
            withAttributes: attributes
        )
    }

    private static func postalAddressLines(_ address: PostalAddress) -> String {
        let streetLine = [address.street, address.houseNumber]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
        let cityLine = [address.postalCode, address.city]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
        let trimmedUnit = address.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let unitLine = trimmedUnit.isEmpty
            ? ""
            : (trimmedUnit.lowercased().hasPrefix("top") ? trimmedUnit : "Top \(trimmedUnit)")
        return [streetLine, unitLine, cityLine, address.country.rawValue]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    private static func letterSummary(_ text: String) -> String {
        let maximumLength = 360
        guard text.count > maximumLength else { return text }
        let end = text.index(text.startIndex, offsetBy: maximumLength)
        return String(text[..<end]) + "… (vollständig in Anlage 1)"
    }

    private static let accentColor = UIColor(red: 0.08, green: 0.31, blue: 0.52, alpha: 1)

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_AT")
        formatter.dateStyle = .long
        formatter.timeStyle = .medium
        formatter.timeZone = .autoupdatingCurrent
        return formatter
    }()

    private static let letterDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_AT")
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.timeZone = .autoupdatingCurrent
        return formatter
    }()

    private static func reportScope(for report: IncidentReport, property: ManagedProperty) -> String {
        if report.isCommonArea { return "Allgemeinfläche" }
        return property.occupancyRole == .tenant ? "Gemietetes Objekt" : "Objekt im Eigentum"
    }

    private static func reportSubject(_ report: IncidentReport, property: ManagedProperty) -> String {
        var details = [report.garageLocation.trimmingCharacters(in: .whitespacesAndNewlines)]
            .filter { !$0.isEmpty }
        let plate = report.licensePlate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !plate.isEmpty {
            details.append("Kennzeichen \(plate)")
        }
        if details.isEmpty {
            let summary = report.notes
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
            if !summary.isEmpty {
                details.append(String(summary.prefix(70)))
            }
        }
        let detailText = details.isEmpty ? "Details siehe Anlage 1" : details.joined(separator: ", ")
        return "\(property.officialDisplayName) - \(report.violation) - \(detailText)"
    }

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
