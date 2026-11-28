import Foundation
import HanlinPlatformContracts

public struct HanlinScriptingPerformanceBudgets: Codable, Hashable, Sendable {
    public let schemaVersion: UInt32
    public let archivePreviewP95Milliseconds: UInt64
    public let warmCompileP95Milliseconds: UInt64
    public let coldCompileP95Milliseconds: UInt64
    public let coldLaunchP95Milliseconds: UInt64
    public let eventPatchP95Milliseconds: UInt64
    public let foregroundEngineHeapBytes: Int
    public let widgetSnapshotBytes: Int
    public let widgetDecodeP95Milliseconds: UInt64
    public let toolCancellationP95Milliseconds: UInt64

    public init(
        schemaVersion: UInt32 = 1,
        archivePreviewP95Milliseconds: UInt64,
        warmCompileP95Milliseconds: UInt64,
        coldCompileP95Milliseconds: UInt64,
        coldLaunchP95Milliseconds: UInt64,
        eventPatchP95Milliseconds: UInt64,
        foregroundEngineHeapBytes: Int,
        widgetSnapshotBytes: Int,
        widgetDecodeP95Milliseconds: UInt64,
        toolCancellationP95Milliseconds: UInt64
    ) throws {
        guard schemaVersion == 1,
              archivePreviewP95Milliseconds > 0,
              warmCompileP95Milliseconds > 0,
              coldCompileP95Milliseconds >= warmCompileP95Milliseconds,
              coldLaunchP95Milliseconds > 0,
              eventPatchP95Milliseconds > 0,
              foregroundEngineHeapBytes > 0,
              widgetSnapshotBytes > 0,
              widgetDecodeP95Milliseconds > 0,
              toolCancellationP95Milliseconds > 0
        else {
            throw HanlinContractError.invalidSchema(reason: "invalid Scripting performance budgets")
        }
        self.schemaVersion = schemaVersion
        self.archivePreviewP95Milliseconds = archivePreviewP95Milliseconds
        self.warmCompileP95Milliseconds = warmCompileP95Milliseconds
        self.coldCompileP95Milliseconds = coldCompileP95Milliseconds
        self.coldLaunchP95Milliseconds = coldLaunchP95Milliseconds
        self.eventPatchP95Milliseconds = eventPatchP95Milliseconds
        self.foregroundEngineHeapBytes = foregroundEngineHeapBytes
        self.widgetSnapshotBytes = widgetSnapshotBytes
        self.widgetDecodeP95Milliseconds = widgetDecodeP95Milliseconds
        self.toolCancellationP95Milliseconds = toolCancellationP95Milliseconds
    }

    public static func release() throws -> Self {
        try Self(
            archivePreviewP95Milliseconds: 3_000,
            warmCompileP95Milliseconds: 2_000,
            coldCompileP95Milliseconds: 6_000,
            coldLaunchP95Milliseconds: 1_000,
            eventPatchP95Milliseconds: 33,
            foregroundEngineHeapBytes: 16 << 20,
            widgetSnapshotBytes: 4 << 20,
            widgetDecodeP95Milliseconds: 100,
            toolCancellationP95Milliseconds: 250
        )
    }
}
