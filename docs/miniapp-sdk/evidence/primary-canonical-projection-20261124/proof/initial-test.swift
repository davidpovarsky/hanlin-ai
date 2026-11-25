import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptStore
import Testing

@Suite("Canonical projection of installed package entrypoints")
struct HanlinCanonicalEntrypointProjectionTests {
    @Test("Stored Expo package keeps every action while equivalent exposures share a canonical descriptor")
    func storedExpoActionsRemainDiscoverable() throws {
        let snapshot = try storedSnapshot()
        let originalEntrypoints = snapshot.entrypoints
        let actionIDs = ["hostServicesEcho", "hostServicesFail", "hostServicesPublishWidget"]

        #expect(snapshot.hasLaunchableApp)
        #expect(originalEntrypoints.map(\.id) == ["app"] + actionIDs + ["widget"])
        #expect(originalEntrypoints.filter { $0.kind == .appIntent }.compactMap(\.exportedSymbol) == actionIDs)

        let descriptor = try snapshot.appDescriptor()
        try descriptor.validate()
        #expect(descriptor.entryPoints.map(\.kind) == [.app, .appIntentBridge, .widget])
        let intent = try #require(descriptor.entryPoints.first { $0.kind == .appIntentBridge })
        #expect(intent.handler == "source/bundle.js")
        #expect(intent.runtimeProfile == .hanlinExpo)
        #expect(intent.allowedContexts == [.appIntent, .mainApplication])
        #expect(descriptor.actions.map(\.id.rawValue) == actionIDs)
        #expect(descriptor.actions.map(\.handler) == Array(repeating: "source/bundle.js", count: 3))
        #expect(snapshot.entrypoints == originalEntrypoints)
        #expect(descriptor.supportedExposures.contains(.foregroundApp))
        #expect(descriptor.supportedExposures.contains(.appIntent))
        #expect(descriptor.supportedExposures.contains(.widget))
    }

    @Test("Conflicting canonical exposures remain validation errors",
          arguments: ["handler", "runtime", "contexts"])
    func conflictingCanonicalExposuresRemainInvalid(_ field: String) throws {
        let snapshot = try storedSnapshot(changingLastIntent: field)
        do {
            _ = try snapshot.appDescriptor()
            Issue.record("A differing \(field) must not be hidden by exposure coalescing.")
        } catch let HanlinContractError.invalidManifest(issues) {
            #expect(issues.contains { $0.code == .duplicateEntryPoint && $0.path == "entryPoints" })
        }
    }

    private func storedSnapshot(changingLastIntent field: String? = nil) throws -> HanlinStoredPackageSnapshot {
        var object = try #require(
            JSONSerialization.jsonObject(with: Data(Self.storedCatalogEntryJSON.utf8)) as? [String: Any]
        )
        if let field {
            var entrypoints = try #require(object["entrypoints"] as? [[String: Any]])
            let index = try #require(entrypoints.firstIndex { $0["id"] as? String == "hostServicesPublishWidget" })
            switch field {
            case "handler":
                entrypoints[index]["sourcePath"] = "source/alternate.js"
            case "runtime":
                entrypoints[index]["runtimeProfile"] = HanlinRuntimeProfile.hanlinNativeScript.rawValue
            case "contexts":
                entrypoints[index]["supportedContexts"] = [HanlinExecutionContext.mainApplication.rawValue]
            default:
                Issue.record("Unexpected conflict fixture \(field).")
            }
            object["entrypoints"] = entrypoints
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let entry = try decoder.decode(
            HanlinScriptCatalogEntry.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        let grants = try #require(object["grantedCapabilities"] as? [String])
            .map { try HanlinCapabilityID(validating: $0) }
        return HanlinStoredPackageSnapshot(
            record: entry.record,
            entrypoints: entry.entrypoints,
            enabled: entry.enabled,
            availableGenerations: [entry.record.activeGeneration],
            grantedCapabilities: grants,
            manifest: entry.manifest
        )
    }

    // Exact semantic entry retained from the failed simulator's installed registry.
    // Whole registry SHA-256: 66fea131922d3106c90b0341c4fff02f86de0c06932be22bb21db6d1e0c5fea8.
    // Its third intent has the same supported-context set in the opposite JSON order.
    private static let storedCatalogEntryJSON = #"""
    {
      "enabled": true,
      "entrypoints": [
        {
          "artifactDigest": "171ecc1ab7e2eb33806822a417f0efa95393c096fcd5561e414a84b0b2a2e737",
          "compatibility": "partial",
          "id": "app",
          "kind": "app",
          "requiredCapabilities": [
            {
              "capabilityID": "inter-app.share",
              "purpose": "Declared in package manifest.",
              "required": false,
              "scope": {
                "type": "object",
                "value": []
              }
            },
            {
              "capabilityID": "storage",
              "purpose": "Declared in package manifest.",
              "required": false,
              "scope": {
                "type": "object",
                "value": []
              }
            }
          ],
          "runtimePolicyID": "foreground-app-v1",
          "runtimeProfile": "hanlin-expo",
          "sourcePath": "source/bundle.js",
          "supportedContexts": [
            "mainApplication"
          ]
        },
        {
          "artifactDigest": "171ecc1ab7e2eb33806822a417f0efa95393c096fcd5561e414a84b0b2a2e737",
          "compatibility": "partial",
          "exportedSymbol": "hostServicesEcho",
          "id": "hostServicesEcho",
          "kind": "appIntent",
          "requiredCapabilities": [
            {
              "capabilityID": "inter-app.share",
              "purpose": "Declared in package manifest.",
              "required": false,
              "scope": {
                "type": "object",
                "value": []
              }
            },
            {
              "capabilityID": "storage",
              "purpose": "Declared in package manifest.",
              "required": false,
              "scope": {
                "type": "object",
                "value": []
              }
            }
          ],
          "runtimePolicyID": "prepared-foreground-action-v1",
          "runtimeProfile": "hanlin-expo",
          "sourcePath": "source/bundle.js",
          "supportedContexts": [
            "mainApplication",
            "appIntent"
          ]
        },
        {
          "artifactDigest": "171ecc1ab7e2eb33806822a417f0efa95393c096fcd5561e414a84b0b2a2e737",
          "compatibility": "partial",
          "exportedSymbol": "hostServicesFail",
          "id": "hostServicesFail",
          "kind": "appIntent",
          "requiredCapabilities": [
            {
              "capabilityID": "inter-app.share",
              "purpose": "Declared in package manifest.",
              "required": false,
              "scope": {
                "type": "object",
                "value": []
              }
            },
            {
              "capabilityID": "storage",
              "purpose": "Declared in package manifest.",
              "required": false,
              "scope": {
                "type": "object",
                "value": []
              }
            }
          ],
          "runtimePolicyID": "prepared-foreground-action-v1",
          "runtimeProfile": "hanlin-expo",
          "sourcePath": "source/bundle.js",
          "supportedContexts": [
            "mainApplication",
            "appIntent"
          ]
        },
        {
          "artifactDigest": "171ecc1ab7e2eb33806822a417f0efa95393c096fcd5561e414a84b0b2a2e737",
          "compatibility": "partial",
          "exportedSymbol": "hostServicesPublishWidget",
          "id": "hostServicesPublishWidget",
          "kind": "appIntent",
          "requiredCapabilities": [
            {
              "capabilityID": "inter-app.share",
              "purpose": "Declared in package manifest.",
              "required": false,
              "scope": {
                "type": "object",
                "value": []
              }
            },
            {
              "capabilityID": "storage",
              "purpose": "Declared in package manifest.",
              "required": false,
              "scope": {
                "type": "object",
                "value": []
              }
            }
          ],
          "runtimePolicyID": "prepared-foreground-action-v1",
          "runtimeProfile": "hanlin-expo",
          "sourcePath": "source/bundle.js",
          "supportedContexts": [
            "appIntent",
            "mainApplication"
          ]
        },
        {
          "artifactDigest": "171ecc1ab7e2eb33806822a417f0efa95393c096fcd5561e414a84b0b2a2e737",
          "compatibility": "partial",
          "id": "widget",
          "kind": "widget",
          "requiredCapabilities": [
            {
              "capabilityID": "inter-app.share",
              "purpose": "Declared in package manifest.",
              "required": false,
              "scope": {
                "type": "object",
                "value": []
              }
            },
            {
              "capabilityID": "storage",
              "purpose": "Declared in package manifest.",
              "required": false,
              "scope": {
                "type": "object",
                "value": []
              }
            }
          ],
          "runtimePolicyID": "widget-v1",
          "runtimeProfile": "hanlin-expo",
          "sourcePath": "widgets/widget.json",
          "supportedContexts": [
            "widget"
          ],
          "widgetEngine": "expo"
        }
      ],
      "grantedCapabilities": [
        "inter-app.share",
        "storage"
      ],
      "manifest": {
        "actions": [
          {
            "capability": "inter-app.share",
            "handler": "bundle.js",
            "id": "hostServicesEcho",
            "title": "Host Services roundtrip"
          },
          {
            "capability": "inter-app.share",
            "handler": "bundle.js",
            "id": "hostServicesFail",
            "title": "Host Services failure"
          },
          {
            "capability": "inter-app.share",
            "handler": "bundle.js",
            "id": "hostServicesPublishWidget",
            "title": "Host Services prepared widget publication"
          }
        ],
        "author": {
          "name": "Hanlin Expo Runtime Team"
        },
        "capabilities": [
          "storage",
          "inter-app.share"
        ],
        "color": "#4A90E2",
        "contributors": [],
        "description": "Dynamic Expo MiniApp Variant A rendering Apple SwiftUI.",
        "entry": "bundle.js",
        "entrypoints": [
          {
            "exportedSymbol": "hostServicesEcho",
            "id": "hostServicesEcho",
            "kind": "appIntent",
            "sourcePath": "bundle.js"
          },
          {
            "exportedSymbol": "hostServicesFail",
            "id": "hostServicesFail",
            "kind": "appIntent",
            "sourcePath": "bundle.js"
          },
          {
            "exportedSymbol": "hostServicesPublishWidget",
            "id": "hostServicesPublishWidget",
            "kind": "appIntent",
            "sourcePath": "bundle.js"
          }
        ],
        "hanlinRuntime": "hanlin-expo",
        "hanlinWidget": {
          "abiVersion": 1,
          "actions": [],
          "families": [
            "systemSmall",
            "systemMedium",
            "systemLarge",
            "systemExtraLarge"
          ],
          "sourceFormat": "tsx"
        },
        "icon": "sparkles",
        "intentInputTypes": [],
        "localizedDescriptions": {},
        "localizedNames": {},
        "name": "Expo SwiftUI Probe A",
        "runInApp": false,
        "version": "1.0.0",
        "widgetEngine": "expo"
      },
      "record": {
        "activeGeneration": 10,
        "artifactDigest": "171ecc1ab7e2eb33806822a417f0efa95393c096fcd5561e414a84b0b2a2e737",
        "installedAt": 1795559488607.047,
        "installedPackageID": "install-script-ec17057f5a2c82aaed6ab6ca",
        "packageID": "script-ec17057f5a2c82aaed6ab6ca",
        "schemaVersion": 1,
        "sourceDigest": "e9b662011c5ef37c2cf4491f4c6516b86886a1d0e93104cec534745395f8076a",
        "updatedAt": 1795560102231.4758,
        "version": "1.0.0"
      }
    }
    """#
}
