import Foundation
import ImageIO

enum ImageTimestampSource: String, Codable, Sendable {
    case exifOriginal = "EXIF DateTimeOriginal"
    case exifDigitized = "EXIF DateTimeDigitized"
    case tiff = "TIFF DateTime"
    case cameraClock = "Geräteuhr bei Kameraaufnahme"
    case unavailable = "Nicht verfügbar"
}

struct EvidenceImageTimestamp: Codable, Equatable, Sendable {
    let capturedAt: Date?
    let rawValue: String?
    let source: ImageTimestampSource
    let timeZoneWasEmbedded: Bool
    let interpretedTimeZone: String?
}

enum EvidenceImageMetadataReader {
    static func read(
        from data: Data,
        photoSource: EvidencePhotoSource,
        importedAt: Date
    ) -> EvidenceImageTimestamp {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            return cameraFallback(for: photoSource, importedAt: importedAt)
        }

        let exif = properties[kCGImagePropertyExifDictionary] as? NSDictionary
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? NSDictionary

        if let raw = exif?[kCGImagePropertyExifDateTimeOriginal] as? String {
            return parse(
                raw,
                offset: exif?[kCGImagePropertyExifOffsetTimeOriginal] as? String,
                source: .exifOriginal
            )
        }
        if let raw = exif?[kCGImagePropertyExifDateTimeDigitized] as? String {
            return parse(
                raw,
                offset: exif?[kCGImagePropertyExifOffsetTimeDigitized] as? String,
                source: .exifDigitized
            )
        }
        if let raw = tiff?[kCGImagePropertyTIFFDateTime] as? String {
            return parse(raw, offset: nil, source: .tiff)
        }
        return cameraFallback(for: photoSource, importedAt: importedAt)
    }

    private static func parse(
        _ rawValue: String,
        offset: String?,
        source: ImageTimestampSource
    ) -> EvidenceImageTimestamp {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)

        let date: Date?
        let embeddedTimeZone: Bool
        if let offset, !offset.isEmpty {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ssXXXXX"
            date = formatter.date(from: rawValue + offset)
            embeddedTimeZone = true
        } else {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            formatter.timeZone = .autoupdatingCurrent
            date = formatter.date(from: rawValue)
            embeddedTimeZone = false
        }

        return EvidenceImageTimestamp(
            capturedAt: date,
            rawValue: rawValue,
            source: source,
            timeZoneWasEmbedded: embeddedTimeZone,
            interpretedTimeZone: embeddedTimeZone ? offset : TimeZone.autoupdatingCurrent.identifier
        )
    }

    private static func cameraFallback(
        for source: EvidencePhotoSource,
        importedAt: Date
    ) -> EvidenceImageTimestamp {
        guard source == .camera else {
            return EvidenceImageTimestamp(
                capturedAt: nil,
                rawValue: nil,
                source: .unavailable,
                timeZoneWasEmbedded: false,
                interpretedTimeZone: nil
            )
        }
        return EvidenceImageTimestamp(
            capturedAt: importedAt,
            rawValue: nil,
            source: .cameraClock,
            timeZoneWasEmbedded: true,
            interpretedTimeZone: TimeZone.autoupdatingCurrent.identifier
        )
    }
}
