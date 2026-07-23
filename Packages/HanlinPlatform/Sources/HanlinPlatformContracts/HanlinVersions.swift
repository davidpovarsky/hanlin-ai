import Foundation

public protocol HanlinMajorMinorVersion:
    RawRepresentable,
    Codable,
    Hashable,
    Comparable,
    CustomStringConvertible,
    Sendable
where RawValue == String {
    static var versionKind: String { get }
    var major: UInt16 { get }
    var minor: UInt16 { get }
    init(major: UInt16, minor: UInt16)
}

extension HanlinMajorMinorVersion {
    public init?(rawValue: String) {
        guard let parsed = Self.parse(rawValue) else {
            return nil
        }
        self.init(major: parsed.major, minor: parsed.minor)
    }

    public init(validating rawValue: String) throws {
        guard let parsed = Self.parse(rawValue) else {
            throw HanlinContractError.invalidVersion(
                kind: Self.versionKind,
                value: rawValue
            )
        }
        self.init(major: parsed.major, minor: parsed.minor)
    }

    public var rawValue: String {
        "\(major).\(minor)"
    }

    public var description: String {
        rawValue
    }

    public static func < (left: Self, right: Self) -> Bool {
        (left.major, left.minor) < (right.major, right.minor)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(validating: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func parse(_ value: String) -> (major: UInt16, minor: UInt16)? {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 2 else {
            return nil
        }
        guard components.allSatisfy({ component in
            !component.isEmpty &&
                component.allSatisfy(\.isNumber) &&
                (component == "0" || component.first != "0")
        }) else {
            return nil
        }
        guard
            let major = UInt16(components[0]),
            let minor = UInt16(components[1])
        else {
            return nil
        }
        return (major, minor)
    }
}

public struct HanlinAPIVersion: HanlinMajorMinorVersion {
    public static let versionKind = "API"
    public let major: UInt16
    public let minor: UInt16
    public init(major: UInt16, minor: UInt16) {
        self.major = major
        self.minor = minor
    }
}

public struct HanlinManifestVersion: HanlinMajorMinorVersion {
    public static let versionKind = "manifest"
    public let major: UInt16
    public let minor: UInt16
    public init(major: UInt16, minor: UInt16) {
        self.major = major
        self.minor = minor
    }
}

public struct HanlinWireProtocolVersion: HanlinMajorMinorVersion {
    public static let versionKind = "wire protocol"
    public let major: UInt16
    public let minor: UInt16
    public init(major: UInt16, minor: UInt16) {
        self.major = major
        self.minor = minor
    }
}

public struct HanlinPackageVersion:
    RawRepresentable,
    Codable,
    Hashable,
    Comparable,
    CustomStringConvertible,
    Sendable
{
    public let major: UInt32
    public let minor: UInt32
    public let patch: UInt32
    public let prerelease: [String]
    public let buildMetadata: [String]

    public init(
        major: UInt32,
        minor: UInt32,
        patch: UInt32,
        prerelease: [String] = [],
        buildMetadata: [String] = []
    ) throws {
        guard Self.validateIdentifiers(prerelease, allowLeadingZeroes: false) else {
            throw HanlinContractError.invalidVersion(
                kind: "package",
                value: "\(major).\(minor).\(patch)-\(prerelease.joined(separator: "."))"
            )
        }
        guard Self.validateIdentifiers(buildMetadata, allowLeadingZeroes: true) else {
            throw HanlinContractError.invalidVersion(
                kind: "package",
                value: "\(major).\(minor).\(patch)+\(buildMetadata.joined(separator: "."))"
            )
        }
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        self.buildMetadata = buildMetadata
    }

    public init?(rawValue: String) {
        guard let parsed = Self.parse(rawValue) else {
            return nil
        }
        guard let value = try? Self(
            major: parsed.major,
            minor: parsed.minor,
            patch: parsed.patch,
            prerelease: parsed.prerelease,
            buildMetadata: parsed.buildMetadata
        ) else {
            return nil
        }
        self = value
    }

    public init(validating rawValue: String) throws {
        guard let value = Self(rawValue: rawValue) else {
            throw HanlinContractError.invalidVersion(kind: "package", value: rawValue)
        }
        self = value
    }

    public var rawValue: String {
        var value = "\(major).\(minor).\(patch)"
        if !prerelease.isEmpty {
            value += "-\(prerelease.joined(separator: "."))"
        }
        if !buildMetadata.isEmpty {
            value += "+\(buildMetadata.joined(separator: "."))"
        }
        return value
    }

    public var description: String {
        rawValue
    }

    public static func < (left: Self, right: Self) -> Bool {
        let numericLeft = (left.major, left.minor, left.patch)
        let numericRight = (right.major, right.minor, right.patch)
        if numericLeft != numericRight {
            return numericLeft < numericRight
        }
        if left.prerelease.isEmpty {
            if !right.prerelease.isEmpty {
                return false
            }
            return left.buildMetadata.lexicographicallyPrecedes(
                right.buildMetadata
            )
        }
        if right.prerelease.isEmpty {
            return true
        }
        for (leftPart, rightPart) in zip(left.prerelease, right.prerelease) {
            if leftPart == rightPart {
                continue
            }
            let leftNumber = UInt64(leftPart)
            let rightNumber = UInt64(rightPart)
            switch (leftNumber, rightNumber) {
            case let (.some(left), .some(right)):
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return leftPart < rightPart
            }
        }
        if left.prerelease.count != right.prerelease.count {
            return left.prerelease.count < right.prerelease.count
        }
        return left.buildMetadata.lexicographicallyPrecedes(
            right.buildMetadata
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(validating: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func parse(
        _ value: String
    ) -> (
        major: UInt32,
        minor: UInt32,
        patch: UInt32,
        prerelease: [String],
        buildMetadata: [String]
    )? {
        let buildSplit = value.split(
            separator: "+",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard buildSplit.count <= 2, buildSplit.allSatisfy({ !$0.isEmpty }) else {
            return nil
        }
        let prereleaseSplit = buildSplit[0].split(
            separator: "-",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard prereleaseSplit.count <= 2, prereleaseSplit.allSatisfy({ !$0.isEmpty }) else {
            return nil
        }
        let numbers = prereleaseSplit[0].split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard
            numbers.count == 3,
            numbers.allSatisfy({
                !$0.isEmpty &&
                    $0.allSatisfy(\.isNumber) &&
                    ($0 == "0" || $0.first != "0")
            }),
            let major = UInt32(numbers[0]),
            let minor = UInt32(numbers[1]),
            let patch = UInt32(numbers[2])
        else {
            return nil
        }
        let prerelease = prereleaseSplit.count == 2
            ? prereleaseSplit[1].split(separator: ".").map(String.init)
            : []
        let build = buildSplit.count == 2
            ? buildSplit[1].split(separator: ".").map(String.init)
            : []
        guard
            validateIdentifiers(prerelease, allowLeadingZeroes: false),
            validateIdentifiers(build, allowLeadingZeroes: true)
        else {
            return nil
        }
        return (major, minor, patch, prerelease, build)
    }

    private static func validateIdentifiers(
        _ values: [String],
        allowLeadingZeroes: Bool
    ) -> Bool {
        values.allSatisfy { value in
            guard !value.isEmpty else {
                return false
            }
            let validCharacters = value.unicodeScalars.allSatisfy { scalar in
                scalar.isASCII &&
                    (CharacterSet.alphanumerics.contains(scalar) || scalar.value == 45)
            }
            guard validCharacters else {
                return false
            }
            if !allowLeadingZeroes,
               value.allSatisfy(\.isNumber),
               value.count > 1,
               value.first == "0"
            {
                return false
            }
            return true
        }
    }
}

public struct HanlinHostVersionRange: Codable, Hashable, Sendable {
    public let minimum: HanlinPackageVersion
    public let maximum: HanlinPackageVersion?

    public init(
        minimum: HanlinPackageVersion,
        maximum: HanlinPackageVersion? = nil
    ) throws {
        if let maximum, maximum < minimum {
            throw HanlinContractError.invalidVersionRange(
                minimum: minimum.rawValue,
                maximum: maximum.rawValue
            )
        }
        self.minimum = minimum
        self.maximum = maximum
    }

    public func contains(_ version: HanlinPackageVersion) -> Bool {
        guard version >= minimum else {
            return false
        }
        return maximum.map { version <= $0 } ?? true
    }

    private enum CodingKeys: String, CodingKey {
        case minimum
        case maximum
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            minimum: container.decode(
                HanlinPackageVersion.self,
                forKey: .minimum
            ),
            maximum: container.decodeIfPresent(
                HanlinPackageVersion.self,
                forKey: .maximum
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(minimum, forKey: .minimum)
        try container.encodeIfPresent(maximum, forKey: .maximum)
    }
}

public struct HanlinVersionSupport: Hashable, Sendable {
    public let api: ClosedRange<HanlinAPIVersion>
    public let manifest: ClosedRange<HanlinManifestVersion>
    public let wireProtocol: ClosedRange<HanlinWireProtocolVersion>

    public init(
        api: ClosedRange<HanlinAPIVersion>,
        manifest: ClosedRange<HanlinManifestVersion>,
        wireProtocol: ClosedRange<HanlinWireProtocolVersion>
    ) {
        self.api = api
        self.manifest = manifest
        self.wireProtocol = wireProtocol
    }

    public static let version1 = HanlinVersionSupport(
        api: HanlinAPIVersion(major: 1, minor: 0) ... HanlinAPIVersion(major: 1, minor: 0),
        manifest: HanlinManifestVersion(major: 1, minor: 0) ... HanlinManifestVersion(major: 1, minor: 0),
        wireProtocol: HanlinWireProtocolVersion(major: 1, minor: 0) ... HanlinWireProtocolVersion(major: 1, minor: 0)
    )

    public func validate(_ version: HanlinAPIVersion) throws {
        guard api.contains(version) else {
            throw HanlinContractError.unsupportedVersion(
                kind: "API",
                received: version.rawValue,
                supported: "\(api.lowerBound.rawValue)...\(api.upperBound.rawValue)"
            )
        }
    }

    public func validate(_ version: HanlinManifestVersion) throws {
        guard manifest.contains(version) else {
            throw HanlinContractError.unsupportedVersion(
                kind: "manifest",
                received: version.rawValue,
                supported: "\(manifest.lowerBound.rawValue)...\(manifest.upperBound.rawValue)"
            )
        }
    }

    public func validate(_ version: HanlinWireProtocolVersion) throws {
        guard wireProtocol.contains(version) else {
            throw HanlinContractError.unsupportedVersion(
                kind: "wire protocol",
                received: version.rawValue,
                supported: "\(wireProtocol.lowerBound.rawValue)...\(wireProtocol.upperBound.rawValue)"
            )
        }
    }
}
