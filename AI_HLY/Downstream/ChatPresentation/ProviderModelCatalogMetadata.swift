import Foundation

struct ProviderModelArchitecture: Codable, Sendable {
    var input_modalities: [String]?
    var output_modalities: [String]?
}

struct ProviderModelCatalogMetadata: Codable, Sendable {
    enum PriceStatus: String, Codable { case free, paid, unknown }
    let schemaVersion: Int
    let provider: String
    let modelID: String
    let canonicalSlug: String?
    let source: String
    let verifiedAt: Date
    let pricingUSD: [String: String]
    let inputModalities: [String]?
    let outputModalities: [String]?
    let supportedParameters: [String]?

    init(modelID: String, canonicalSlug: String? = nil, source: String, verifiedAt: Date = .now,
         pricing: [String: String]?, architecture: ProviderModelArchitecture?, parameters: [String]?) {
        schemaVersion = 1
        provider = "OPENROUTER"
        self.modelID = modelID
        self.canonicalSlug = canonicalSlug
        self.source = source
        self.verifiedAt = verifiedAt
        pricingUSD = pricing ?? [:]
        inputModalities = architecture?.input_modalities
        outputModalities = architecture?.output_modalities
        supportedParameters = parameters
    }

    var isFresh: Bool { Date().timeIntervalSince(verifiedAt) < 24 * 60 * 60 }
    var hasImageOutput: Bool { outputModalities?.contains("image") == true }
    var priceStatus: PriceStatus {
        guard pricingUSD["prompt"] != nil, pricingUSD["completion"] != nil else { return .unknown }
        let parsed = pricingUSD.values.compactMap { Self.rate($0) }
        guard parsed.count == pricingUSD.count else { return .unknown }
        return parsed.allSatisfy { $0 == 0 } ? .free : .paid
    }
    static func rate(_ text: String) -> Decimal? {
        guard text.range(of: #"^[+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$"#, options: .regularExpression) != nil,
              let number = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              !number.isNaN, number >= 0 else { return nil }
        return number
    }
    var rateDescription: String? {
        guard priceStatus != .unknown, let input = pricingUSD["prompt"].flatMap(Self.rate),
              let output = pricingUSD["completion"].flatMap(Self.rate) else { return nil }
        let million = NSDecimalNumber(value: 1_000_000)
        return "$\(NSDecimalNumber(decimal: input).multiplying(by: million).stringValue) in / $\(NSDecimalNumber(decimal: output).multiplying(by: million).stringValue) out · 1M tokens"
    }
}
