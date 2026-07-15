import CoreImage
import Foundation
import Vision

struct VehicleColorSuggestion: Equatable, Sendable {
    let name: String
    let confidence: Float
    let method: String
}

enum VehicleColorAnalyzer {
    static func analyze(imageData: Data) async -> VehicleColorSuggestion? {
        await Task.detached(priority: .userInitiated) {
            try? analyzeSynchronously(imageData: imageData)
        }.value
    }

    private static func analyzeSynchronously(imageData: Data) throws -> VehicleColorSuggestion? {
        guard let image = CIImage(
            data: imageData,
            options: [.applyOrientationProperty: true]
        ) else {
            return nil
        }

        let region = (try? salientRegion(in: imageData)) ?? CGRect(x: 0.15, y: 0.30, width: 0.70, height: 0.50)
        let insetRegion = region.insetBy(dx: region.width * 0.08, dy: region.height * 0.08)
        let extent = image.extent
        let cropRect = CGRect(
            x: extent.minX + insetRegion.minX * extent.width,
            y: extent.minY + insetRegion.minY * extent.height,
            width: insetRegion.width * extent.width,
            height: insetRegion.height * extent.height
        ).intersection(extent)

        guard !cropRect.isNull,
              cropRect.width > 1,
              cropRect.height > 1,
              let croppedImage = CIContext(options: [.cacheIntermediates: false]).createCGImage(image, from: cropRect) else {
            return nil
        }

        let dimension = 64
        let bytesPerRow = dimension * 4
        var pixels = [UInt8](repeating: 0, count: dimension * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: dimension,
            height: dimension,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(croppedImage, in: CGRect(x: 0, y: 0, width: dimension, height: dimension))

        var counts: [String: Int] = [:]
        var consideredPixels = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Float(pixels[index]) / 255
            let green = Float(pixels[index + 1]) / 255
            let blue = Float(pixels[index + 2]) / 255
            let maximum = max(red, green, blue)
            let minimum = min(red, green, blue)
            let saturation = maximum == 0 ? 0 : (maximum - minimum) / maximum

            // Extreme highlights contain little information about the object's actual paint.
            if maximum > 0.96 && saturation < 0.04 { continue }

            let color = colorName(red: red, green: green, blue: blue, brightness: maximum, saturation: saturation)
            counts[color, default: 0] += 1
            consideredPixels += 1
        }

        guard consideredPixels > 0,
              let result = counts.max(by: { $0.value < $1.value }) else {
            return nil
        }
        let confidence = Float(result.value) / Float(consideredPixels)
        guard confidence >= 0.20 else { return nil }

        return VehicleColorSuggestion(
            name: result.key,
            confidence: confidence,
            method: "Dominante Farbe im auffälligen Bildbereich"
        )
    }

    private static func salientRegion(in imageData: Data) throws -> CGRect? {
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(data: imageData)
        try handler.perform([request])
        return request.results?.first?.salientObjects?
            .max(by: { area(of: $0.boundingBox) < area(of: $1.boundingBox) })?
            .boundingBox
    }

    private static func area(of rectangle: CGRect) -> CGFloat {
        rectangle.width * rectangle.height
    }

    private static func colorName(
        red: Float,
        green: Float,
        blue: Float,
        brightness: Float,
        saturation: Float
    ) -> String {
        if brightness < 0.25 { return "Schwarz" }
        if brightness > 0.82 && saturation < 0.16 { return "Weiß" }
        if saturation < 0.18 { return "Grau / Silber" }

        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        let hue: Float
        if delta == 0 {
            hue = 0
        } else if maximum == red {
            hue = 60 * ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == green {
            hue = 60 * (((blue - red) / delta) + 2)
        } else {
            hue = 60 * (((red - green) / delta) + 4)
        }
        let normalizedHue = hue < 0 ? hue + 360 : hue

        switch normalizedHue {
        case 0..<18, 345...360: return "Rot"
        case 18..<45: return "Orange / Braun"
        case 45..<75: return "Gelb"
        case 75..<165: return "Grün"
        case 165..<255: return "Blau"
        case 255..<300: return "Violett"
        default: return "Rot"
        }
    }
}
