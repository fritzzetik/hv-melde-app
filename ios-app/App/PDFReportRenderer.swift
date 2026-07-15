import HVMeldeCore
import UIKit

@MainActor
enum PDFReportRenderer {
    static func render(_ report: IncidentReport) throws -> URL {
        let pageBounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let data = renderer.pdfData { context in
            context.beginPage()
            draw(report, in: pageBounds)
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Meldung-\(report.id.uuidString).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func draw(_ report: IncidentReport, in bounds: CGRect) {
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
            ("Objekt", report.propertyName),
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
}
