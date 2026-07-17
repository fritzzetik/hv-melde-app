import HVMeldeCore
import UIKit

private enum LetterLanguage: Equatable {
    case german, italian, english

    var localeIdentifier: String {
        switch self {
        case .german: "de_AT"
        case .italian: "it_IT"
        case .english: "en_GB"
        }
    }
}

@MainActor
enum PDFReportRenderer {
    struct ReportTextTranslation: Sendable {
        var location: String
        var violation: String
        var notes: String
        var vehicleDescription: String
        var witnesses: String
    }

    static func render(
        _ report: IncidentReport,
        profile: UserProfile,
        property: ManagedProperty,
        management: PropertyManagement?,
        evidencePhotos: [EvidencePhoto],
        technicalAttachmentMode: TechnicalAttachmentMode,
        translatedText: ReportTextTranslation? = nil
    ) throws -> URL {
        let pageBounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let analysisCount = evidencePhotos.filter { $0.confirmedAnalysis != nil }.count
        let technicalPageCount = technicalAttachmentMode == .pdf
            ? 1 + evidencePhotos.count + analysisCount
            : 0
        let letterLanguages = letterLanguages(for: management?.reportLanguage ?? .german)
        let totalPages = letterLanguages.count + evidencePhotos.count + technicalPageCount
        let attachmentTitles = attachmentSummary(
            for: evidencePhotos,
            technicalAttachmentMode: technicalAttachmentMode
        )
        let data = renderer.pdfData { context in
            var pageNumber = 0
            for language in letterLanguages {
                pageNumber += 1
                beginPage(context, in: pageBounds)
                drawLetter(
                    report,
                    profile: profile,
                    property: property,
                    management: management,
                    attachmentTitles: attachmentTitles,
                    technicalAttachmentMode: technicalAttachmentMode,
                    language: language,
                    translatedText: translatedText,
                    in: pageBounds
                )
                drawFooter(report: report, page: pageNumber, totalPages: totalPages, in: pageBounds)
            }

            var attachmentNumber = 1
            for evidencePhoto in evidencePhotos {
                pageNumber += 1
                beginPage(context, in: pageBounds)
                drawEvidencePhoto(evidencePhoto, attachmentNumber: attachmentNumber, in: pageBounds)
                drawFooter(report: report, page: pageNumber, totalPages: totalPages, in: pageBounds)
                attachmentNumber += 1
            }

            if technicalAttachmentMode == .pdf {
                pageNumber += 1
                beginPage(context, in: pageBounds)
                drawCaseDetails(
                    report,
                    profile: profile,
                    property: property,
                    management: management,
                    attachmentNumber: attachmentNumber,
                    in: pageBounds
                )
                drawFooter(report: report, page: pageNumber, totalPages: totalPages, in: pageBounds)
                attachmentNumber += 1

                for evidencePhoto in evidencePhotos {
                    pageNumber += 1
                    beginPage(context, in: pageBounds)
                    drawTechnicalEvidencePhoto(evidencePhoto, attachmentNumber: attachmentNumber, in: pageBounds)
                    drawFooter(report: report, page: pageNumber, totalPages: totalPages, in: pageBounds)
                    attachmentNumber += 1
                    if let analysis = evidencePhoto.confirmedAnalysis {
                        pageNumber += 1
                        beginPage(context, in: pageBounds)
                        drawConfirmedAnalysis(analysis, attachmentNumber: attachmentNumber, in: pageBounds)
                        drawFooter(report: report, page: pageNumber, totalPages: totalPages, in: pageBounds)
                        attachmentNumber += 1
                    }
                }
            }
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Meldung-\(report.id.uuidString).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func letterLanguages(for preference: ReportLanguage) -> [LetterLanguage] {
        switch preference {
        case .german: [.german]
        case .italian: [.italian]
        case .english: [.english]
        case .germanItalian: [.german, .italian]
        }
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
            "Anlage \(attachmentNumber) - Beweisfoto",
            at: y,
            width: contentWidth,
            font: .boldSystemFont(ofSize: 20),
            color: textColor,
            margin: margin
        ) + 18

        if let image = UIImage(data: photo.data) {
            let maximumImageSize = CGSize(width: contentWidth, height: 590)
            let scale = min(maximumImageSize.width / image.size.width, maximumImageSize.height / image.size.height)
            let imageSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let imageRect = CGRect(
                x: margin + (contentWidth - imageSize.width) / 2,
                y: y,
                width: imageSize.width,
                height: imageSize.height
            )
            image.draw(in: imageRect)
            y = imageRect.maxY + 18
        }

        if let capturedAt = photo.imageTimestamp.capturedAt {
            y = drawText(
                "Aufgenommen am \(dateFormatter.string(from: capturedAt))",
                at: y,
                width: contentWidth,
                font: .systemFont(ofSize: 10.5),
                color: secondaryTextColor,
                margin: margin
            ) + 10
        }

        if let description = photo.confirmedAnalysis?.confirmedSceneSummary,
           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = drawText(
                letterSummary(description),
                at: y,
                width: contentWidth,
                font: .systemFont(ofSize: 11),
                color: textColor,
                margin: margin
            )
        }
    }

    private static func drawTechnicalEvidencePhoto(
        _ photo: EvidencePhoto,
        attachmentNumber: Int,
        in bounds: CGRect
    ) {
        let margin: CGFloat = 48
        let contentWidth = bounds.width - (2 * margin)
        var y = margin

        y = drawText(
            "Technische Anlage \(attachmentNumber) - Fotodaten",
            at: y,
            width: contentWidth,
            font: .boldSystemFont(ofSize: 20),
            color: textColor,
            margin: margin
        ) + 14

        if let image = UIImage(data: photo.data) {
            let maximumImageSize = CGSize(width: contentWidth, height: 330)
            let scale = min(maximumImageSize.width / image.size.width, maximumImageSize.height / image.size.height)
            let imageSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let imageRect = CGRect(
                x: margin + (contentWidth - imageSize.width) / 2,
                y: y,
                width: imageSize.width,
                height: imageSize.height
            )
            image.draw(in: imageRect)
            y = imageRect.maxY + 14
        }

        let captureValue = photo.imageTimestamp.capturedAt.map {
            dateFormatter.string(from: $0)
        } ?? "Nicht in den Bildmetadaten vorhanden"
        let timeZoneValue: String
        if photo.imageTimestamp.timeZoneWasEmbedded {
            timeZoneValue = "Im Bild enthalten bzw. durch die Geräteuhr bestimmt (\(photo.imageTimestamp.interpretedTimeZone ?? "unbekannt"))"
        } else if let interpretedTimeZone = photo.imageTimestamp.interpretedTimeZone {
            timeZoneValue = "Nicht im Bild enthalten; als \(interpretedTimeZone) interpretiert"
        } else {
            timeZoneValue = "Nicht verfügbar"
        }

        let rows: [(String, String)] = [
            ("Fotoquelle", photo.source.rawValue),
            ("Aufnahmezeit des Bildes", captureValue),
            ("Zeitquelle", photo.imageTimestamp.source.rawValue),
            ("Zeitzonenangabe", timeZoneValue),
            ("Originaler Metadatenwert", photo.imageTimestamp.rawValue ?? "Nicht verfügbar"),
            ("In die App übernommen", dateFormatter.string(from: photo.importedAt)),
            ("SHA-256 des Originalbilds", photo.sha256.chunked(every: 32).joined(separator: " "))
        ]

        for (label, value) in rows {
            y = drawText(label.uppercased(), at: y, width: contentWidth, font: .boldSystemFont(ofSize: 8), color: secondaryTextColor, margin: margin) + 2
            y = drawText(
                value,
                at: y,
                width: contentWidth,
                font: label.contains("SHA-256") ? .monospacedSystemFont(ofSize: 9, weight: .regular) : .systemFont(ofSize: 10),
                color: textColor,
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
            "Technische Anlage \(attachmentNumber) - Bildauswertung",
            at: y,
            width: contentWidth,
            font: .boldSystemFont(ofSize: 20),
            color: textColor,
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
                color: secondaryTextColor,
                margin: margin
            ) + 3
            y = drawText(
                value,
                at: y,
                width: contentWidth,
                font: .systemFont(ofSize: 12),
                color: textColor,
                margin: margin
            ) + 13
        }

        _ = drawText(
            "Diese Angaben wurden lokal vorgeschlagen und anschließend in der App bestätigt. Die Konfidenz ist ein technischer Hinweis und keine Tatsachenfeststellung.",
            at: y + 18,
            width: contentWidth,
            font: .systemFont(ofSize: 9),
            color: secondaryTextColor,
            margin: margin
        )
    }

    private static func drawLetter(
        _ report: IncidentReport,
        profile: UserProfile,
        property: ManagedProperty,
        management: PropertyManagement?,
        attachmentTitles: [String],
        technicalAttachmentMode: TechnicalAttachmentMode,
        language: LetterLanguage,
        translatedText: ReportTextTranslation?,
        in bounds: CGRect
    ) {
        let copy = LetterCopy(language: language)
        let usesTranslation = language != .german && translatedText != nil
        let location = usesTranslation ? translatedText!.location : report.garageLocation
        let violation = usesTranslation ? translatedText!.violation : report.violation
        let notes = usesTranslation ? translatedText!.notes : report.notes
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
            color: secondaryTextColor,
            margin: margin
        )
        drawRightAlignedText(
            copy.documentTitle,
            at: y,
            font: .boldSystemFont(ofSize: 8),
            color: accentColor,
            rightMargin: margin,
            in: bounds
        )
        drawLine(at: 54, margin: margin, width: contentWidth, color: accentColor)

        let recipientName = management?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var recipientLines = [
            recipientName?.isEmpty == false ? recipientName! : copy.defaultRecipient
        ]
        if let management, !management.address.formatted.isEmpty {
            recipientLines.append(postalAddressLines(management.address))
        } else if !property.reportEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recipientLines.append("\(copy.byEmail): \(property.reportEmail)")
        }

        y = 78
        y = drawText(
            recipientLines.joined(separator: "\n"),
            at: y,
            width: 290,
            font: .systemFont(ofSize: 10.5),
            color: textColor,
            margin: margin
        )

        drawRightAlignedText(
            letterDateFormatter(for: language).string(from: report.createdAt),
            at: max(154, y + 12),
            font: .systemFont(ofSize: 10.5),
            color: textColor,
            rightMargin: margin,
            in: bounds
        )
        y = max(198, y + 52)

        y = drawText(
            reportSubject(report, property: property, language: language, violation: violation, location: location),
            at: y,
            width: contentWidth,
            font: .boldSystemFont(ofSize: 15),
            color: textColor,
            margin: margin
        ) + 23

        y = drawText(
            copy.salutation,
            at: y,
            width: contentWidth,
            font: .systemFont(ofSize: 11.5),
            color: textColor,
            margin: margin
        ) + 15

        if usesTranslation {
            y = drawText(
                copy.translationNotice,
                at: y,
                width: contentWidth,
                font: .boldSystemFont(ofSize: 9.5),
                color: accentColor,
                margin: margin
            ) + 12
        }

        y = drawText(
            copy.introduction(isCommonArea: report.isCommonArea, occupancyRole: property.occupancyRole),
            at: y,
            width: contentWidth,
            font: .systemFont(ofSize: 11.5),
            color: textColor,
            margin: margin
        ) + 16

        var factLines = [
            "\(copy.objectLabel): \(property.officialDisplayName)",
            "\(copy.objectTypeLabel): \(copy.propertyType(property.propertyType))",
            "\(copy.objectAddressLabel): \(property.address.formatted)",
            "\(copy.observedLabel): \(dateFormatter(for: language).string(from: report.incidentAt))",
            "\(copy.locationLabel): \(location)",
            "\(copy.reasonLabel): \(violation)"
        ]
        if !report.licensePlate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            factLines.append("\(copy.licensePlateLabel): \(report.licensePlate)")
        }
        let boxHeight = CGFloat(factLines.count) * 15 + 20
        let boxRect = CGRect(x: margin, y: y, width: contentWidth, height: boxHeight)
        panelBackgroundColor.setFill()
        UIBezierPath(roundedRect: boxRect, cornerRadius: 8).fill()
        _ = drawText(
            factLines.joined(separator: "\n"),
            at: y + 10,
            width: contentWidth - 24,
            font: .systemFont(ofSize: 10.5),
            color: textColor,
            margin: margin + 12
        )
        y = boxRect.maxY + 17

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            y = drawText(
                copy.summaryTitle,
                at: y,
                width: contentWidth,
                font: .boldSystemFont(ofSize: 9),
                color: secondaryTextColor,
                margin: margin
            ) + 4
            y = drawText(
                letterSummary(trimmedNotes),
                at: y,
                width: contentWidth,
                font: .systemFont(ofSize: 11),
                color: textColor,
                margin: margin
            ) + 15
        }

        let responseSentence = report.wantsManagementResponse
            ? copy.responseRequested
            : copy.responseNotRequired
        let disclosureSentence = report.permitsNameDisclosure
            ? copy.disclosureAllowed
            : copy.disclosureDenied
        y = drawText(
            copy.responseTitle,
            at: y,
            width: contentWidth,
            font: .boldSystemFont(ofSize: 9),
            color: secondaryTextColor,
            margin: margin
        ) + 4
        y = drawText(
            "\(responseSentence) \(disclosureSentence)",
            at: y,
            width: contentWidth,
            font: .systemFont(ofSize: 11),
            color: textColor,
            margin: margin
        ) + 15

        if !attachmentTitles.isEmpty {
            let attachmentSentence = technicalAttachmentMode == .json
                ? copy.jsonAttachmentSentence
                : copy.attachmentSentence
            y = drawText(
                attachmentSentence,
                at: y,
                width: contentWidth,
                font: .systemFont(ofSize: 11),
                color: textColor,
                margin: margin
            ) + 18
        }

        y = drawText(
            "\(copy.closing)\n\n\(profile.fullName)",
            at: y,
            width: contentWidth,
            font: .systemFont(ofSize: 11),
            color: textColor,
            margin: margin
        ) + 18

        if !attachmentTitles.isEmpty {
            _ = drawText(
                "\(copy.attachmentsTitle)\n" + attachmentTitles.map(copy.localizeAttachmentTitle).joined(separator: "\n"),
                at: y,
                width: contentWidth,
                font: .systemFont(ofSize: 9.5),
                color: secondaryTextColor,
                margin: margin
            )
        }
    }

    private static func attachmentSummary(
        for photos: [EvidencePhoto],
        technicalAttachmentMode: TechnicalAttachmentMode
    ) -> [String] {
        var titles: [String] = []
        if photos.count == 1 {
            titles.append("1. Beweisfoto")
        } else if photos.count > 1 {
            titles.append("1-\(photos.count). \(photos.count) Beweisfotos")
        }

        if technicalAttachmentMode == .pdf {
            let analysisCount = photos.filter { $0.confirmedAnalysis != nil }.count
            let firstNumber = photos.count + 1
            let lastNumber = photos.count + 1 + photos.count + analysisCount
            let numberRange = firstNumber == lastNumber
                ? "\(firstNumber)."
                : "\(firstNumber)-\(lastNumber)."
            titles.append("\(numberRange) Technische Dokumentation")
        } else if technicalAttachmentMode == .json {
            titles.append("Technische Daten (separate JSON-Datei)")
        }
        return titles
    }

    private static func drawCaseDetails(
        _ report: IncidentReport,
        profile: UserProfile,
        property: ManagedProperty,
        management: PropertyManagement?,
        attachmentNumber: Int,
        in bounds: CGRect
    ) {
        let margin: CGFloat = 48
        let contentWidth = bounds.width - (2 * margin)
        var y = margin

        y = drawText(
            "Technische Anlage \(attachmentNumber) - Falldaten",
            at: y,
            width: contentWidth,
            font: .boldSystemFont(ofSize: 20),
            color: textColor,
            margin: margin
        ) + 9

        y = drawText(
            "Strukturierte Zusammenfassung der in der App bestätigten Angaben.",
            at: y,
            width: contentWidth,
            font: .systemFont(ofSize: 9),
            color: secondaryTextColor,
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
            ("Zeugen", report.witnesses),
            ("Rückmeldung der Hausverwaltung", report.wantsManagementResponse ? "Erwünscht" : "Nicht erforderlich"),
            ("Weitergabe des Namens", report.permitsNameDisclosure ? "Erlaubt" : "Nicht erlaubt")
        ]

        for (label, value) in rows where !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            y = drawText(
                label.uppercased(),
                at: y,
                width: contentWidth,
                font: .boldSystemFont(ofSize: 8),
                color: secondaryTextColor,
                margin: margin
            ) + 2
            y = drawText(
                value,
                at: y,
                width: contentWidth,
                font: .systemFont(ofSize: 10.5),
                color: textColor,
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
        drawLine(at: 786, margin: margin, width: width, color: separatorColor)
        _ = drawText(
            "Lokal erstellt. Kein externer oder qualifizierter Zeitstempel.",
            at: 794,
            width: width - 120,
            font: .systemFont(ofSize: 7),
            color: secondaryTextColor,
            margin: margin
        )
        _ = drawText(
            "Meldungs-ID: \(report.id.uuidString)",
            at: 808,
            width: width - 90,
            font: .monospacedSystemFont(ofSize: 6.5, weight: .regular),
            color: secondaryTextColor,
            margin: margin
        )
        drawRightAlignedText(
            "Seite \(page) von \(totalPages)",
            at: 808,
            font: .systemFont(ofSize: 7),
            color: secondaryTextColor,
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

    private static func beginPage(_ context: UIGraphicsPDFRendererContext, in bounds: CGRect) {
        context.beginPage()
        pageBackgroundColor.setFill()
        UIRectFill(bounds)
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
        let cleaned = text
            .replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let maximumLength = 500
        guard cleaned.count > maximumLength else { return cleaned }
        let end = cleaned.index(cleaned.startIndex, offsetBy: maximumLength)
        return String(cleaned[..<end]) + "…"
    }

    // PDF output must not use semantic UIKit colors. On iOS 27 beta these
    // can resolve with a dark appearance even though the PDF page is white.
    private static let pageBackgroundColor = UIColor.white
    private static let textColor = UIColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1)
    private static let secondaryTextColor = UIColor(red: 0.36, green: 0.38, blue: 0.42, alpha: 1)
    private static let panelBackgroundColor = UIColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1)
    private static let separatorColor = UIColor(red: 0.72, green: 0.74, blue: 0.77, alpha: 1)
    private static let accentColor = UIColor(red: 0.08, green: 0.31, blue: 0.52, alpha: 1)

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_AT")
        formatter.dateStyle = .long
        formatter.timeStyle = .medium
        formatter.timeZone = .autoupdatingCurrent
        return formatter
    }()

    private static func dateFormatter(for language: LetterLanguage) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.dateStyle = .long
        formatter.timeStyle = .medium
        formatter.timeZone = .autoupdatingCurrent
        return formatter
    }

    private static func letterDateFormatter(for language: LetterLanguage) -> DateFormatter {
        let formatter = dateFormatter(for: language)
        formatter.timeStyle = .none
        return formatter
    }

    private static func reportScope(for report: IncidentReport, property: ManagedProperty) -> String {
        if report.isCommonArea { return "Allgemeinfläche" }
        return property.occupancyRole == .tenant ? "Gemietetes Objekt" : "Objekt im Eigentum"
    }

    private static func reportSubject(
        _ report: IncidentReport,
        property: ManagedProperty,
        language: LetterLanguage,
        violation: String,
        location: String
    ) -> String {
        let copy = LetterCopy(language: language)
        var details = [location.trimmingCharacters(in: .whitespacesAndNewlines)]
            .filter { !$0.isEmpty }
        let plate = report.licensePlate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !plate.isEmpty {
            details.append("\(copy.licensePlateLabel) \(plate)")
        }
        if details.isEmpty {
            let summary = report.notes
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
            if !summary.isEmpty {
                details.append(String(summary.prefix(70)))
            }
        }
        let detailText = details.isEmpty ? copy.detailsInAttachment : details.joined(separator: ", ")
        return "\(property.officialDisplayName) - \(violation) - \(detailText)"
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

private struct LetterCopy {
    let language: LetterLanguage

    var documentTitle: String { value("MELDUNG", "SEGNALAZIONE", "REPORT") }
    var defaultRecipient: String { value("An die zuständige Hausverwaltung", "All'amministrazione condominiale competente", "To the responsible property management") }
    var byEmail: String { value("per E-Mail", "via e-mail", "by email") }
    var salutation: String { value("Sehr geehrte Damen und Herren,", "Gentili Signore e Signori,", "Dear Sir or Madam,") }
    var translationNotice: String { value(
        "KI-übersetzt. Verbindlich ist die deutsche Originalfassung.",
        "Traduzione automatica tramite IA. Fa fede la versione originale in tedesco.",
        "AI-translated. The binding version is the German original."
    ) }
    var objectLabel: String { value("Objekt", "Immobile", "Property") }
    var objectTypeLabel: String { value("Objekttyp", "Tipo di immobile", "Property type") }
    var objectAddressLabel: String { value("Objektanschrift", "Indirizzo dell'immobile", "Property address") }
    var observedLabel: String { value("Beobachtet", "Osservato il", "Observed") }
    var locationLabel: String { value("Bereich", "Area", "Location") }
    var reasonLabel: String { value("Meldegrund", "Motivo della segnalazione", "Reason for report") }
    var licensePlateLabel: String { value("Kennzeichen", "Targa", "Registration plate") }
    var summaryTitle: String { value("Kurzbeschreibung", "Breve descrizione", "Summary") }
    var responseTitle: String { value("Rückmeldung und Vertraulichkeit", "Riscontro e riservatezza", "Response and confidentiality") }
    var responseRequested: String { value(
        "Ich ersuche um eine kurze Rückmeldung zum Ergebnis der Prüfung beziehungsweise zum weiteren Vorgehen.",
        "Chiedo un breve riscontro sull'esito della verifica e sulle eventuali misure successive.",
        "I kindly request a brief response regarding the outcome of the review and any further action."
    ) }
    var responseNotRequired: String { value(
        "Eine gesonderte Rückmeldung der Hausverwaltung ist nicht erforderlich.",
        "Non è necessario un riscontro separato da parte dell'amministrazione.",
        "A separate response from the property management is not required."
    ) }
    var disclosureAllowed: String { value(
        "Mein Name darf der verursachenden Person mitgeteilt werden.",
        "Il mio nome può essere comunicato alla persona responsabile.",
        "My name may be disclosed to the person responsible."
    ) }
    var disclosureDenied: String { value(
        "Ich ersuche darum, meinen Namen gegenüber der verursachenden Person nicht offenzulegen.",
        "Chiedo che il mio nome non venga comunicato alla persona responsabile.",
        "Please do not disclose my name to the person responsible."
    ) }
    var jsonAttachmentSentence: String { value(
        "Die Beweisfotos finden Sie im PDF. Technische Daten sind zusätzlich als maschinenlesbare JSON-Datei beigefügt.",
        "Le fotografie probatorie sono incluse nel PDF. I dati tecnici sono inoltre allegati in un file JSON leggibile da sistemi informatici.",
        "The evidence photographs are included in the PDF. Technical data is also attached as a machine-readable JSON file."
    ) }
    var attachmentSentence: String { value(
        "Die zugehörigen Beweisfotos und gegebenenfalls die technische Dokumentation finden Sie in den Anlagen.",
        "Le relative fotografie probatorie e, se previsto, la documentazione tecnica sono riportate negli allegati.",
        "The related evidence photographs and, where applicable, the technical documentation are included in the attachments."
    ) }
    var closing: String { value("Mit freundlichen Grüßen", "Cordiali saluti", "Yours faithfully") }
    var attachmentsTitle: String { value("Anlagen", "Allegati", "Attachments") }
    var detailsInAttachment: String { value("Details siehe Anlage 1", "Dettagli nell'allegato 1", "See attachment 1 for details") }

    func introduction(isCommonArea: Bool, occupancyRole: OccupancyRole) -> String {
        switch language {
        case .german:
            let scope = isCommonArea
                ? "auf einer Allgemeinfläche des unten genannten Objekts"
                : (occupancyRole == .tenant ? "in meinem gemieteten Objekt" : "in meinem Eigentumsobjekt")
            return "Hiermit informiere ich Sie über einen dokumentierten Vorfall \(scope). Ich ersuche um Prüfung und gegebenenfalls um die erforderlichen Maßnahmen."
        case .italian:
            let scope = isCommonArea
                ? "in un'area comune dell'immobile indicato di seguito"
                : (occupancyRole == .tenant ? "nell'immobile da me condotto in locazione" : "nel mio immobile di proprietà")
            return "Con la presente segnalo un episodio documentato \(scope). Chiedo una verifica e, se necessario, l'adozione delle misure opportune."
        case .english:
            let scope = isCommonArea
                ? "in a common area of the property stated below"
                : (occupancyRole == .tenant ? "in the property I rent" : "in my owned property")
            return "I hereby report a documented incident \(scope). Please review the matter and take any action considered necessary."
        }
    }

    func propertyType(_ type: PropertyType) -> String {
        switch (language, type) {
        case (.german, _): type.rawValue
        case (.italian, .apartment): "Appartamento"
        case (.italian, .garage): "Garage"
        case (.italian, .commercialSpace): "Locale commerciale"
        case (.italian, .basement): "Cantina"
        case (.italian, .storage): "Deposito"
        case (.italian, .other): "Altro"
        case (.english, .apartment): "Apartment"
        case (.english, .garage): "Garage"
        case (.english, .commercialSpace): "Commercial premises"
        case (.english, .basement): "Basement"
        case (.english, .storage): "Storage"
        case (.english, .other): "Other"
        }
    }

    func localizeAttachmentTitle(_ title: String) -> String {
        guard language != .german else { return title }
        let replacements: [(String, String)] = language == .italian
            ? [("Beweisfotos", "fotografie probatorie"), ("Beweisfoto", "fotografia probatoria"), ("Technische Dokumentation", "Documentazione tecnica"), ("Technische Daten", "Dati tecnici"), ("separate JSON-Datei", "file JSON separato")]
            : [("Beweisfotos", "evidence photographs"), ("Beweisfoto", "evidence photograph"), ("Technische Dokumentation", "Technical documentation"), ("Technische Daten", "Technical data"), ("separate JSON-Datei", "separate JSON file")]
        return replacements.reduce(title) { result, item in
            result.replacingOccurrences(of: item.0, with: item.1)
        }
    }

    private func value(_ german: String, _ italian: String, _ english: String) -> String {
        switch language {
        case .german: german
        case .italian: italian
        case .english: english
        }
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
