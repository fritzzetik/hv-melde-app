import Foundation

public enum ReportCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case unauthorizedVehicle = "Unberechtigt abgestelltes Fahrzeug"
    case blockedAccess = "Zufahrt oder Durchgang blockiert"
    case outsideParkingSpace = "Fahrzeug außerhalb des Stellplatzes"
    case bulkyWaste = "Sperrmüll oder unerlaubte Ablagerung"
    case contamination = "Verschmutzung"
    case damage = "Beschädigung"
    case other = "Sonstiges"

    public var id: String { rawValue }

    public var defaultViolation: String {
        rawValue
    }

    public var expectsVehicle: Bool {
        switch self {
        case .unauthorizedVehicle, .blockedAccess, .outsideParkingSpace:
            true
        case .bulkyWaste, .contamination, .damage, .other:
            false
        }
    }
}

public struct OCRTextCandidate: Equatable, Sendable {
    public let text: String
    public let confidence: Float

    public init(text: String, confidence: Float) {
        self.text = text
        self.confidence = confidence
    }
}

public struct LicensePlateCandidate: Equatable, Identifiable, Sendable {
    public let text: String
    public let confidence: Float

    public var id: String { text }

    public init(text: String, confidence: Float) {
        self.text = text
        self.confidence = confidence
    }
}

public enum LicensePlateParser {
    public static func candidates(from observations: [OCRTextCandidate]) -> [LicensePlateCandidate] {
        var bestByPlate: [String: Float] = [:]

        for observation in observations {
            let normalized = normalize(observation.text)
            guard isPlausiblePlate(normalized) else { continue }
            let confidence = min(1, observation.confidence + formatBonus(for: normalized))
            bestByPlate[normalized] = max(bestByPlate[normalized] ?? 0, confidence)
        }

        return bestByPlate
            .map { LicensePlateCandidate(text: displayFormat($0.key), confidence: $0.value) }
            .sorted {
                if $0.confidence == $1.confidence { return $0.text < $1.text }
                return $0.confidence > $1.confidence
            }
    }

    private static func normalize(_ text: String) -> String {
        text.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func isPlausiblePlate(_ value: String) -> Bool {
        guard (5...10).contains(value.count),
              value.contains(where: \.isLetter),
              value.contains(where: \.isNumber) else {
            return false
        }
        return value.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }

    private static func formatBonus(for value: String) -> Float {
        let patterns = [
            "^[A-Z]{2}[0-9]{3}[A-Z]{2}$",     // Italien
            "^[A-Z]{1,3}[0-9]{1,6}[A-Z]{0,2}$", // Österreich/Schweiz/Liechtenstein
            "^[A-Z]{1,3}[A-Z]{0,2}[0-9]{1,4}$"  // Deutschland, kompakt gelesen
        ]
        return patterns.contains(where: { value.range(of: $0, options: .regularExpression) != nil }) ? 0.15 : 0.05
    }

    private static func displayFormat(_ value: String) -> String {
        if value.range(of: "^[A-Z]{2}[0-9]{3}[A-Z]{2}$", options: .regularExpression) != nil {
            let firstEnd = value.index(value.startIndex, offsetBy: 2)
            let secondEnd = value.index(firstEnd, offsetBy: 3)
            return "\(value[..<firstEnd]) \(value[firstEnd...])"
        }
        return value
    }
}

public struct ImageClassificationLabel: Equatable, Sendable {
    public let identifier: String
    public let confidence: Float

    public init(identifier: String, confidence: Float) {
        self.identifier = identifier
        self.confidence = confidence
    }
}

public struct VehicleDetection: Equatable, Sendable {
    public let detected: Bool
    public let confidence: Float

    public init(detected: Bool, confidence: Float) {
        self.detected = detected
        self.confidence = confidence
    }
}

public enum VehicleAnalysisInterpreter {
    private static let vehicleTerms = [
        "car", "vehicle", "automobile", "sedan", "hatchback", "minivan",
        "suv", "jeep", "taxi", "cab", "pickup", "truck",
        "pkw", "auto", "fahrzeug"
    ]

    public static func detectVehicle(in labels: [ImageClassificationLabel]) -> VehicleDetection {
        let matches = labels.filter { label in
            let identifier = label.identifier.lowercased()
            let words = identifier.split { !$0.isLetter }.map(String.init)
            return vehicleTerms.contains(where: words.contains) || identifier.contains("station wagon")
        }
        let confidence = matches.map(\.confidence).max() ?? 0
        return VehicleDetection(detected: confidence >= 0.15, confidence: confidence)
    }
}

public struct VehicleTypeSuggestion: Equatable, Sendable {
    public let name: String
    public let confidence: Float
    public let sourceLabel: String

    public init(name: String, confidence: Float, sourceLabel: String) {
        self.name = name
        self.confidence = confidence
        self.sourceLabel = sourceLabel
    }
}

public struct SceneObjectSuggestion: Equatable, Identifiable, Sendable {
    public let name: String
    public let confidence: Float
    public let sourceLabel: String

    public var id: String { name }

    public init(name: String, confidence: Float, sourceLabel: String) {
        self.name = name
        self.confidence = confidence
        self.sourceLabel = sourceLabel
    }
}

public enum SceneDetailInterpreter {
    private static let vehicleTypes: [(terms: [String], name: String)] = [
        (["station wagon", "estate car"], "Kombi"),
        (["hatchback"], "Kompaktwagen / Schrägheck"),
        (["sport utility", "suv", "jeep"], "SUV"),
        (["minivan", "passenger van"], "Van"),
        (["pickup", "pickup truck"], "Pickup"),
        (["truck", "lorry"], "Lkw"),
        (["convertible", "cabriolet"], "Cabriolet"),
        (["coupe", "sports car"], "Coupé / Sportwagen"),
        (["sedan", "saloon car"], "Limousine"),
        (["motorcycle", "motorbike"], "Motorrad"),
        (["car", "automobile", "motor vehicle"], "Pkw")
    ]

    private static let sceneObjects: [(terms: [String], name: String, minimumConfidence: Float)] = [
        (["mattress"], "Matratze", 0.03),
        (["bed frame", "bedstead"], "Bettgestell", 0.04),
        (["sofa", "couch"], "Sofa", 0.04),
        (["furniture"], "Möbelstück", 0.06),
        (["garbage", "trash", "rubbish", "refuse", "junk", "bulky waste"], "Abfall / Sperrmüll", 0.05),
        (["cardboard", "carton"], "Karton", 0.06),
        (["tire", "tyre"], "Reifen", 0.05),
        (["bicycle", "bike"], "Fahrrad", 0.08)
    ]

    public static func vehicleType(in labels: [ImageClassificationLabel]) -> VehicleTypeSuggestion? {
        for mapping in vehicleTypes {
            if let best = bestMatch(for: mapping.terms, in: labels), best.confidence >= 0.08 {
                return VehicleTypeSuggestion(
                    name: mapping.name,
                    confidence: best.confidence,
                    sourceLabel: best.identifier
                )
            }
        }
        return nil
    }

    public static func relevantObjects(in labels: [ImageClassificationLabel]) -> [SceneObjectSuggestion] {
        sceneObjects.compactMap { mapping in
            guard let best = bestMatch(for: mapping.terms, in: labels),
                  best.confidence >= mapping.minimumConfidence else {
                return nil
            }
            return SceneObjectSuggestion(
                name: mapping.name,
                confidence: best.confidence,
                sourceLabel: best.identifier
            )
        }
        .sorted { $0.confidence > $1.confidence }
    }

    private static func bestMatch(
        for terms: [String],
        in labels: [ImageClassificationLabel]
    ) -> ImageClassificationLabel? {
        labels
            .filter { label in
                let normalized = label.identifier.lowercased()
                return terms.contains { term in
                    normalized == term ||
                    normalized.contains(", \(term)") ||
                    normalized.contains("\(term),") ||
                    normalized.contains(term)
                }
            }
            .max { $0.confidence < $1.confidence }
    }
}
