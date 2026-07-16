import Foundation

public struct ReportCategory: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var defaultViolation: String
    public var expectsVehicle: Bool
    public var isEnabled: Bool
    public var isDeleted: Bool
    public var sortOrder: Int
    public var updatedAt: Date

    public init(
        id: String = "custom.\(UUID().uuidString.lowercased())",
        name: String,
        defaultViolation: String = "",
        expectsVehicle: Bool = false,
        isEnabled: Bool = true,
        isDeleted: Bool = false,
        sortOrder: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.defaultViolation = defaultViolation.isEmpty ? name : defaultViolation
        self.expectsVehicle = expectsVehicle
        self.isEnabled = isEnabled
        self.isDeleted = isDeleted
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
    }

    public var rawValue: String { name }
    public var isBuiltIn: Bool { id.hasPrefix("builtin.") }

    public static let unauthorizedVehicle = builtIn(
        "unauthorizedVehicle", "Unberechtigt abgestelltes Fahrzeug", vehicle: true, order: 0
    )
    public static let blockedAccess = builtIn(
        "blockedAccess", "Zufahrt oder Durchgang blockiert", vehicle: true, order: 1
    )
    public static let outsideParkingSpace = builtIn(
        "outsideParkingSpace", "Fahrzeug außerhalb des Stellplatzes", vehicle: true, order: 2
    )
    public static let bulkyWaste = builtIn(
        "bulkyWaste", "Sperrmüll oder unerlaubte Ablagerung", order: 3
    )
    public static let contamination = builtIn("contamination", "Verschmutzung", order: 4)
    public static let damage = builtIn("damage", "Beschädigung", order: 5)
    public static let heating = builtIn("heating", "Heizung oder Warmwasser", order: 6)
    public static let waterDamage = builtIn("waterDamage", "Wasser- oder Feuchtigkeitsschaden", order: 7)
    public static let lighting = builtIn("lighting", "Defekte Beleuchtung", order: 8)
    public static let elevator = builtIn("elevator", "Aufzug", order: 9)
    public static let accessSystem = builtIn("accessSystem", "Türen, Tore oder Schlösser", order: 10)
    public static let noise = builtIn("noise", "Lärmbelästigung", order: 11)
    public static let cleaning = builtIn("cleaning", "Reinigung", order: 12)
    public static let pests = builtIn("pests", "Schädlingsbefall", order: 13)
    public static let fireSafety = builtIn("fireSafety", "Brandschutz oder Gefahr", order: 14)
    public static let commonFacilities = builtIn("commonFacilities", "Gemeinschaftsanlagen", order: 15)
    public static let vandalism = builtIn("vandalism", "Vandalismus", order: 16)
    public static let other = builtIn("other", "Sonstiges", order: 17)

    public static let defaultCategories: [ReportCategory] = [
        .unauthorizedVehicle, .blockedAccess, .outsideParkingSpace, .bulkyWaste,
        .contamination, .damage, .heating, .waterDamage, .lighting, .elevator,
        .accessSystem, .noise, .cleaning, .pests, .fireSafety, .commonFacilities,
        .vandalism, .other
    ]

    public static var allCases: [ReportCategory] { defaultCategories }

    private static func builtIn(
        _ key: String,
        _ name: String,
        vehicle: Bool = false,
        order: Int
    ) -> ReportCategory {
        ReportCategory(
            id: "builtin.\(key)",
            name: name,
            defaultViolation: name,
            expectsVehicle: vehicle,
            sortOrder: order,
            updatedAt: .distantPast
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, defaultViolation, expectsVehicle, isEnabled, isDeleted, sortOrder, updatedAt
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let legacyName = try? container.decode(String.self) {
            if let builtIn = Self.defaultCategories.first(where: { $0.name == legacyName }) {
                self = builtIn
            } else {
                self = ReportCategory(
                    id: "legacy.\(Data(legacyName.utf8).base64EncodedString())",
                    name: legacyName,
                    updatedAt: .distantPast
                )
            }
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        defaultViolation = try container.decodeIfPresent(String.self, forKey: .defaultViolation) ?? name
        expectsVehicle = try container.decodeIfPresent(Bool.self, forKey: .expectsVehicle) ?? false
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
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
    private static let vehicleTypes: [(terms: [String], name: String, minimumConfidence: Float)] = [
        (["station wagon", "estate car"], "Kombi", 0.45),
        (["hatchback"], "Kompaktwagen / Schrägheck", 0.45),
        (["sport utility", "suv", "jeep"], "SUV", 0.45),
        (["minivan", "passenger van"], "Van", 0.45),
        (["pickup", "pickup truck"], "Pickup", 0.45),
        (["truck", "lorry"], "Lkw", 0.45),
        (["convertible", "cabriolet"], "Cabriolet", 0.45),
        (["coupe", "sports car"], "Coupé / Sportwagen", 0.45),
        (["sedan", "saloon car"], "Limousine", 0.45),
        (["motorcycle", "motorbike"], "Motorrad", 0.45),
        (["car", "automobile", "motor vehicle"], "Pkw", 0.15)
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
            if let best = bestMatch(for: mapping.terms, in: labels),
               best.confidence >= mapping.minimumConfidence {
                return VehicleTypeSuggestion(
                    name: mapping.name,
                    confidence: best.confidence,
                    sourceLabel: best.identifier
                )
            }
        }
        return nil
    }

    public static func relevantObjects(
        in labels: [ImageClassificationLabel],
        category: ReportCategory? = nil
    ) -> [SceneObjectSuggestion] {
        sceneObjects.compactMap { mapping in
            if category?.expectsVehicle == true,
               mapping.name == "Reifen" || mapping.name == "Fahrrad" {
                return nil
            }
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
                    if term.contains(" ") {
                        return normalized.contains(term)
                    }
                    let words = normalized.split { !$0.isLetter && !$0.isNumber }
                    return words.contains { String($0) == term }
                }
            }
            .max { $0.confidence < $1.confidence }
    }
}
