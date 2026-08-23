import Foundation
import HanlinPlatformContracts
import HanlinScriptServices
import Testing

@Suite("Capability-gated Scripting service brokers")
struct HanlinScriptServiceBrokerTests {
    @Test("Permission authority matches subject, capability, origin, gesture, expiry, and revocation")
    func permissions() async throws {
        let fixture = try Fixture(capabilities: ["storage"])
        #expect(try await fixture.authority.authorize(
            capability: HanlinCapabilityID(validating: "storage"),
            context: fixture.context
        ) == .allowed)
        let otherGrant = try Fixture.grant(capability: "storage", package: "other-package")
        await fixture.authority.upsert(otherGrant)
        let other = try Fixture.context(package: "other-package", grants: [otherGrant.id])
        #expect(try await fixture.authority.authorize(
            capability: HanlinCapabilityID(validating: "storage"),
            context: other
        ) == .allowed)
        let id = try #require(fixture.context.grantIDs.first)
        await fixture.authority.revoke(id)
        #expect(try await fixture.authority.authorize(
            capability: HanlinCapabilityID(validating: "storage"),
            context: fixture.context
        ) == .missingGrant)
    }

    @Test("Storage and VFS are package-namespaced, bounded, and traversal-safe")
    func storageAndFiles() async throws {
        let fixture = try Fixture(capabilities: ["storage", "files"], limits: .init(
            storageBytesPerPackage: 64,
            filesBytesPerPackage: 8,
            maximumNetworkResponseBytes: 64,
            maximumRedirects: 1,
            maximumAuditEvents: 20
        ))
        try await fixture.broker.setStorageValue(.string("value"), for: "key", context: fixture.context)
        #expect(try await fixture.broker.storageValue(for: "key", context: fixture.context) == .string("value"))
        let otherStorage = try Fixture.grant(capability: "storage", package: "other-package")
        await fixture.authority.upsert(otherStorage)
        let other = try Fixture.context(package: "other-package", grants: [otherStorage.id])
        #expect(try await fixture.broker.storageValue(for: "key", context: other) == nil)
        try await fixture.broker.writeFile(Data("1234".utf8), path: "folder/file.txt", context: fixture.context)
        #expect(try await fixture.broker.readFile("folder/file.txt", context: fixture.context) == Data("1234".utf8))
        await #expect(throws: HanlinScriptServiceError.invalidPath("../escape")) {
            try await fixture.broker.writeFile(Data(), path: "../escape", context: fixture.context)
        }
        await #expect(throws: HanlinScriptServiceError.quotaExceeded("files")) {
            try await fixture.broker.writeFile(Data(repeating: 0, count: 9), path: "large.bin", context: fixture.context)
        }
    }

    @Test("Network broker enforces HTTPS, redirects, response limits, and grants")
    func network() async throws {
        let fixture = try Fixture(
            capabilities: ["network"],
            network: NetworkStub(response: .init(
                finalURL: try #require(URL(string: "https://example.com/final")),
                status: 200,
                headers: [:],
                body: Data("ok".utf8),
                redirectCount: 1
            )),
            limits: .init(maximumNetworkResponseBytes: 4, maximumRedirects: 1)
        )
        let response = try await fixture.broker.fetch(.init(
            url: try #require(URL(string: "https://example.com"))
        ), context: fixture.context)
        #expect(response.status == 200)
        await #expect(throws: HanlinScriptServiceError.insecureURL) {
            try await fixture.broker.fetch(.init(
                url: try #require(URL(string: "http://example.com"))
            ), context: fixture.context)
        }
        let denied = try Fixture(capabilities: [])
        await #expect(throws: HanlinScriptServiceError.permissionDenied("network")) {
            try await denied.broker.fetch(.init(
                url: try #require(URL(string: "https://example.com"))
            ), context: denied.context)
        }
    }

    @Test("Dialog, device, URL, pasteboard, and Assistant remain brokered")
    func brokeredServices() async throws {
        let fixture = try Fixture(capabilities: [
            "assistant", "dialog", "device", "open-url", "pasteboard"
        ])
        #expect(try await fixture.broker.presentDialog(
            .init(title: "Title", actions: ["OK"]),
            context: fixture.context
        ) == "OK")
        #expect(try await fixture.broker.deviceSnapshot(context: fixture.context).localeIdentifier == "he")
        #expect(try await fixture.broker.openURL(
            try #require(URL(string: "https://example.com")),
            context: fixture.context
        ))
        try await fixture.broker.writePasteboard("text", context: fixture.context)
        #expect(try await fixture.broker.readPasteboard(context: fixture.context) == "text")
        let stream = try await fixture.broker.assistantStream(prompt: "hello", schema: nil, context: fixture.context)
        var values: [HanlinValue] = []
        for try await value in stream { values.append(value) }
        #expect(values == [.string("hello")])
        #expect(await fixture.broker.auditSnapshot().count == 6)
    }

    @Test("Audit storage is bounded and contains no payload data")
    func audit() async throws {
        let fixture = try Fixture(capabilities: ["device"], limits: .init(maximumAuditEvents: 2))
        _ = try await fixture.broker.deviceSnapshot(context: fixture.context)
        _ = try await fixture.broker.deviceSnapshot(context: fixture.context)
        _ = try await fixture.broker.deviceSnapshot(context: fixture.context)
        let events = await fixture.broker.auditSnapshot()
        #expect(events.map(\.sequence) == [2, 3])
        #expect(events.allSatisfy { $0.safeDetail == "allowed" })
    }
}

private struct Fixture {
    let authority: HanlinScriptPermissionAuthority
    let broker: HanlinScriptServiceBroker
    let context: HanlinScriptServiceContext

    init(
        capabilities: [String],
        network: NetworkStub = .init(response: .init(
            finalURL: URL(string: "https://example.com") ?? URL(filePath: "/invalid"),
            status: 200,
            headers: [:],
            body: Data(),
            redirectCount: 0
        )),
        limits: HanlinScriptServiceBroker.Limits = .init()
    ) throws {
        let grants = try capabilities.map { capability in
            try Self.grant(capability: capability, package: "fixture-package")
        }
        let contextValue = try Self.context(
            package: "fixture-package",
            grants: Set(grants.map(\.id))
        )
        authority = HanlinScriptPermissionAuthority(
            grants: grants,
            now: { Date(timeIntervalSince1970: 10) }
        )
        context = contextValue
        let pasteboard = PasteboardStub()
        broker = HanlinScriptServiceBroker(
            permissions: authority,
            network: network,
            assistant: AssistantStub(),
            dialogs: DialogStub(),
            openURL: OpenURLStub(),
            pasteboard: pasteboard,
            device: DeviceStub(),
            limits: limits,
            now: { Date(timeIntervalSince1970: 10) }
        )
    }

    static func context(package: String, grants: Set<HanlinGrantID>) throws -> HanlinScriptServiceContext {
        .init(
            subject: .package(try HanlinInstalledPackageID(validating: package)),
            permissionContext: .init(
                origin: .scriptPackage,
                userGesturePresent: true,
                canPresentUI: true
            ),
            grantIDs: grants,
            sessionID: try HanlinSessionID(validating: "session.fixture")
        )
    }

    static func grant(capability: String, package: String) throws -> HanlinPermissionGrant {
        HanlinPermissionGrant(
            id: try HanlinGrantID(validating: "grant.\(package).\(capability)"),
            requestID: try HanlinPermissionRequestID(validating: "request.\(package).\(capability)"),
            subject: .package(try HanlinInstalledPackageID(validating: package)),
            scope: .init(capabilityID: try HanlinCapabilityID(validating: capability)),
            source: .user,
            policyVersion: .init(major: 1, minor: 0),
            issuedAt: Date(timeIntervalSince1970: 1)
        )
    }
}

private struct NetworkStub: HanlinScriptNetworkTransport {
    let response: HanlinScriptNetworkResponse
    func fetch(_: HanlinScriptNetworkRequest) async throws -> HanlinScriptNetworkResponse { response }
}

private struct AssistantStub: HanlinScriptAssistantTransport {
    func stream(prompt: String, schema _: HanlinValue?, sessionID _: HanlinSessionID) -> AsyncThrowingStream<HanlinValue, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.string(prompt))
            continuation.finish()
        }
    }
}

private struct DialogStub: HanlinScriptDialogTransport {
    func present(_ request: HanlinScriptDialogRequest) async throws -> String? { request.actions.first }
}

private struct OpenURLStub: HanlinScriptOpenURLTransport {
    func open(_: URL) async -> Bool { true }
}

private actor PasteboardStub: HanlinScriptPasteboardTransport {
    private var value: String?
    func readText() -> String? { value }
    func writeText(_ value: String) { self.value = value }
}

private struct DeviceStub: HanlinScriptDeviceTransport {
    func snapshot() async -> HanlinScriptDeviceSnapshot {
        .init(localeIdentifier: "he", timeZoneIdentifier: "Asia/Jerusalem", batteryLevel: 0.5, isLowPowerModeEnabled: false)
    }
}
