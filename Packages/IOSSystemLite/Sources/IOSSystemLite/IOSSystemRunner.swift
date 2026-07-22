import Foundation
import Synchronization
import ios_system

public struct IOSSystemExecution: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
}

public enum IOSSystemRegistrationFailureCategory: String, Codable, Sendable {
    case resourceMissing
    case malformedDictionary
    case dictionaryCatalogMismatch
    case initializationFailure
    case commandNotRegistered
    case commandNotExecutable
}

public struct IOSSystemRegistrationError: Error, Codable, LocalizedError, Sendable {
    public let category: IOSSystemRegistrationFailureCategory
    public let code: String
    public let message: String
    public let resourcePath: String?
    public let missingCommands: [String]
    public let unexpectedCommands: [String]
    public let underlyingErrorDomain: String?
    public let underlyingErrorCode: Int?

    public var errorDescription: String? { message }

    public init(
        category: IOSSystemRegistrationFailureCategory,
        code: String,
        message: String,
        resourcePath: String? = nil,
        missingCommands: [String] = [],
        unexpectedCommands: [String] = [],
        underlyingError: Error? = nil
    ) {
        let nsError = underlyingError.map { $0 as NSError }
        self.category = category
        self.code = code
        self.message = message
        self.resourcePath = resourcePath
        self.missingCommands = missingCommands
        self.unexpectedCommands = unexpectedCommands
        underlyingErrorDomain = nsError?.domain
        underlyingErrorCode = nsError?.code
    }
}

public struct IOSSystemRegistrationReport: Codable, Sendable {
    public let mainBundlePath: String
    public let moduleBundlePath: String
    public let mainDictionaryPath: String
    public let extraDictionaryPath: String
    public let moduleDictionaryPath: String
    public let dictionaryCommands: [String]
    public let registeredCommands: [String]
    public let executableCommands: [String]
    public let missingRegisteredCommands: [String]
    public let missingExecutableCommands: [String]
    public let rawCommandsClass: String
    public let rawCommandsCount: Int
    public let rawCommandValues: [String]
    public let sideLoadingEnabled: Bool
    public let initializeEnvironmentCallCount: Int
}

public enum IOSSystemRunner {
    public static let linkedCommands: Set<String> = [
        "awk", "cat", "cp", "curl", "grep", "head", "ln", "ls", "mkdir", "mv",
        "readlink", "rm", "rmdir", "sed", "sort", "stat", "tail", "tar", "touch",
        "tr", "uniq", "unlink", "wc"
    ]

    private enum RegistrationState: Sendable {
        case uninitialized
        case initialized(IOSSystemRegistrationReport)
        case failed(IOSSystemRegistrationError)
    }

    private static let registrationState = Mutex<RegistrationState>(.uninitialized)
    private static let executionLock = Mutex<Void>(())

    public static func registrationReport() throws -> IOSSystemRegistrationReport {
        try registrationState.withLock { state in
            switch state {
            case .initialized(let report):
                return report
            case .failed(let error):
                throw error
            case .uninitialized:
                do {
                    let report = try initializeRegistration()
                    state = .initialized(report)
                    return report
                } catch let error as IOSSystemRegistrationError {
                    state = .failed(error)
                    throw error
                } catch {
                    let wrapped = IOSSystemRegistrationError(
                        category: .initializationFailure,
                        code: "unexpected_initialization_error",
                        message: "ios_system registration failed unexpectedly: \(error.localizedDescription)",
                        underlyingError: error
                    )
                    state = .failed(wrapped)
                    throw wrapped
                }
            }
        }
    }

    public static func availableCommands() throws -> [String] {
        let report = try registrationReport()
        guard report.missingRegisteredCommands.isEmpty else {
            throw IOSSystemRegistrationError(
                category: .commandNotRegistered,
                code: "command_not_registered",
                message: "Some approved ios_system commands were not registered: \(report.missingRegisteredCommands.joined(separator: ", ")).",
                missingCommands: report.missingRegisteredCommands
            )
        }
        guard report.missingExecutableCommands.isEmpty else {
            throw IOSSystemRegistrationError(
                category: .commandNotExecutable,
                code: "command_not_executable",
                message: "Some registered ios_system commands are not executable: \(report.missingExecutableCommands.joined(separator: ", ")).",
                missingCommands: report.missingExecutableCommands
            )
        }
        return report.executableCommands
    }

    public static func execute(
        tokens: [String],
        workspace: URL,
        environment: [String: String],
        standardInput: Data = Data()
    ) throws -> IOSSystemExecution {
        guard let command = tokens.first, !tokens.isEmpty, linkedCommands.contains(command) else {
            throw NSError(
                domain: "IOSSystemLite",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The command is not linked or allowed."]
            )
        }
        _ = try availableCommands()
        return try executionLock.withLock { _ in
            try executeLocked(
                tokens: tokens,
                workspace: workspace,
                environment: environment,
                standardInput: standardInput
            )
        }
    }

    private static func initializeRegistration() throws -> IOSSystemRegistrationReport {
        let mainBundle = Bundle.main
        let moduleBundle = Bundle.module
        let mainDictionary = try requiredResource(
            named: "commandDictionary",
            in: mainBundle,
            code: "main_command_dictionary_missing"
        )
        let extraDictionary = try requiredResource(
            named: "extraCommandsDictionary",
            in: mainBundle,
            code: "main_extra_dictionary_missing"
        )
        let moduleDictionary = try requiredResource(
            named: "commandDictionary",
            in: moduleBundle,
            code: "module_command_dictionary_missing"
        )

        let mainCommands = try parseCommandDictionary(at: mainDictionary)
        let moduleCommands = try parseCommandDictionary(at: moduleDictionary)
        let extraCommands = try parsePropertyListDictionary(at: extraDictionary)
        let expected = linkedCommands
        let actual = Set(mainCommands.keys)
        let missing = expected.subtracting(actual).sorted()
        let unexpected = actual.subtracting(expected).sorted()
        guard missing.isEmpty, unexpected.isEmpty else {
            throw IOSSystemRegistrationError(
                category: .dictionaryCatalogMismatch,
                code: "main_dictionary_catalog_mismatch",
                message: "The main ios_system dictionary does not exactly match the approved command catalog.",
                resourcePath: mainDictionary.path,
                missingCommands: missing,
                unexpectedCommands: unexpected
            )
        }
        guard mainCommands == moduleCommands else {
            throw IOSSystemRegistrationError(
                category: .dictionaryCatalogMismatch,
                code: "module_dictionary_catalog_mismatch",
                message: "The IOSSystemLite module dictionary differs from the main application dictionary.",
                resourcePath: moduleDictionary.path
            )
        }
        guard extraCommands.isEmpty else {
            throw IOSSystemRegistrationError(
                category: .dictionaryCatalogMismatch,
                code: "extra_dictionary_not_empty",
                message: "The restricted extra ios_system command dictionary must be empty.",
                resourcePath: extraDictionary.path,
                unexpectedCommands: extraCommands.keys.sorted()
            )
        }
        initializeEnvironment()

        guard let rawCommands = commandsAsArray() else {
            throw IOSSystemRegistrationError(
                category: .initializationFailure,
                code: "commands_array_nil",
                message: "ios_system returned no registered command array after initialization."
            )
        }
        let bridgedArray = rawCommands as NSArray
        var normalizedCommands: [String] = []
        normalizedCommands.reserveCapacity(rawCommands.count)
        for value in rawCommands {
            if let string = value as? String {
                normalizedCommands.append(string)
            } else if let string = value as? NSString {
                normalizedCommands.append(string as String)
            } else {
                throw IOSSystemRegistrationError(
                    category: .initializationFailure,
                    code: "commands_array_bridge_failure",
                    message: "ios_system returned a non-string command value of type \(String(describing: type(of: value)))."
                )
            }
        }

        let registered = Array(Set(normalizedCommands)).sorted()
        let registeredSet = Set(registered)
        let unexpectedRegistered = registeredSet.subtracting(expected).sorted()
        guard unexpectedRegistered.isEmpty else {
            throw IOSSystemRegistrationError(
                category: .initializationFailure,
                code: "unexpected_registered_commands",
                message: "ios_system registered commands outside the approved catalog.",
                unexpectedCommands: unexpectedRegistered
            )
        }
        let missingRegistered = expected.subtracting(registeredSet).sorted()
        let executable = expected.sorted().filter { command in
            command.withCString { ios_executable($0) == 1 }
        }
        let missingExecutable = expected.subtracting(executable).sorted()

        return IOSSystemRegistrationReport(
            mainBundlePath: mainBundle.bundlePath,
            moduleBundlePath: moduleBundle.bundlePath,
            mainDictionaryPath: mainDictionary.path,
            extraDictionaryPath: extraDictionary.path,
            moduleDictionaryPath: moduleDictionary.path,
            dictionaryCommands: actual.sorted(),
            registeredCommands: registered,
            executableCommands: executable,
            missingRegisteredCommands: missingRegistered,
            missingExecutableCommands: missingExecutable,
            rawCommandsClass: NSStringFromClass(type(of: bridgedArray)),
            rawCommandsCount: rawCommands.count,
            rawCommandValues: normalizedCommands,
            sideLoadingEnabled: false,
            initializeEnvironmentCallCount: 1
        )
    }

    private static func requiredResource(
        named name: String,
        in bundle: Bundle,
        code: String
    ) throws -> URL {
        guard let url = bundle.url(forResource: name, withExtension: "plist") else {
            throw IOSSystemRegistrationError(
                category: .resourceMissing,
                code: code,
                message: "Required ios_system resource \(name).plist is missing from \(bundle.bundlePath).",
                resourcePath: bundle.bundlePath
            )
        }
        return url
    }

    private static func parseCommandDictionary(at url: URL) throws -> [String: [String]] {
        let dictionary = try parsePropertyListDictionary(at: url)
        var commands: [String: [String]] = [:]
        for (command, rawEntry) in dictionary {
            guard let values = rawEntry as? [Any], values.count == 4 else {
                throw malformedDictionary(
                    at: url,
                    code: "invalid_command_entry",
                    message: "Command \(command) must contain exactly four metadata values."
                )
            }
            var normalized: [String] = []
            for value in values {
                if let string = value as? String {
                    normalized.append(string)
                } else if let string = value as? NSString {
                    normalized.append(string as String)
                } else {
                    throw malformedDictionary(
                        at: url,
                        code: "invalid_command_metadata_type",
                        message: "Command \(command) metadata values must be strings."
                    )
                }
            }
            commands[command] = normalized
        }
        return commands
    }

    private static func parsePropertyListDictionary(at url: URL) throws -> [String: Any] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw IOSSystemRegistrationError(
                category: .resourceMissing,
                code: "resource_unreadable",
                message: "Required ios_system resource could not be read: \(url.lastPathComponent).",
                resourcePath: url.path,
                underlyingError: error
            )
        }
        do {
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            guard let dictionary = object as? [String: Any] else {
                throw malformedDictionary(
                    at: url,
                    code: "dictionary_root_type_invalid",
                    message: "The root property-list value must be a dictionary."
                )
            }
            return dictionary
        } catch let error as IOSSystemRegistrationError {
            throw error
        } catch {
            throw IOSSystemRegistrationError(
                category: .malformedDictionary,
                code: "property_list_parse_failed",
                message: "ios_system resource is not a valid property list: \(url.lastPathComponent).",
                resourcePath: url.path,
                underlyingError: error
            )
        }
    }

    private static func malformedDictionary(
        at url: URL,
        code: String,
        message: String
    ) -> IOSSystemRegistrationError {
        IOSSystemRegistrationError(
            category: .malformedDictionary,
            code: code,
            message: message,
            resourcePath: url.path
        )
    }

    private static func executeLocked(
        tokens: [String],
        workspace: URL,
        environment: [String: String],
        standardInput: Data
    ) throws -> IOSSystemExecution {
        guard ios_setMiniRootURL(workspace) == 1 else {
            throw NSError(
                domain: "IOSSystemLite",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "ios_system rejected the workspace miniRoot."]
            )
        }
        ios_setDirectoryURL(workspace)

        let oldEnvironment = ProcessInfo.processInfo.environment
        for (name, value) in environment { setenv(name, value, 1) }
        defer {
            for name in environment.keys where oldEnvironment[name] == nil { unsetenv(name) }
            for (name, value) in oldEnvironment where environment[name] != nil { setenv(name, value, 1) }
        }

        guard let input = tmpfile(), let output = tmpfile(), let error = tmpfile() else {
            throw NSError(
                domain: "IOSSystemLite",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Could not allocate command streams."]
            )
        }
        defer {
            fclose(input)
            fclose(output)
            fclose(error)
        }
        if !standardInput.isEmpty {
            standardInput.withUnsafeBytes { bytes in
                if let baseAddress = bytes.baseAddress {
                    fwrite(baseAddress, 1, bytes.count, input)
                }
            }
            rewind(input)
        }
        ios_setStreams(input, output, error)
        let rendered = tokens.map(shellEscape).joined(separator: " ")
        let status = rendered.withCString { ios_system(UnsafeMutablePointer(mutating: $0)) }
        fflush(output)
        fflush(error)
        return IOSSystemExecution(stdout: read(output), stderr: read(error), exitCode: Int32(status))
    }

    private static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func read(_ file: UnsafeMutablePointer<FILE>) -> String {
        rewind(file)
        var bytes: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = fread(&buffer, 1, buffer.count, file)
            if count == 0 { break }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
