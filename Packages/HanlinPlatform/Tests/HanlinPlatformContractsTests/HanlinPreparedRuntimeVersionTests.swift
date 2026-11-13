import HanlinPlatformContracts
import Testing

@Suite("Prepared runtime minimum version contract")
struct HanlinPreparedRuntimeVersionTests {
    @Test func releasedRuntimeMinimumsCannotAdmitMalformedFutureOrPrereleaseVersions() {
        for installed in ["9.1.0", "58.0.3"] {
            #expect(HanlinPreparedRuntimeVersion.supportsMinimum(installed, installed: installed))
            #expect(HanlinPreparedRuntimeVersion.supportsMinimum(" ^" + installed + " ", installed: installed))
            #expect(HanlinPreparedRuntimeVersion.supportsMinimum(installed + "+build.1", installed: installed))
            for malformed in ["", "*", "latest", "9.1", "58.invalid", "3..0", "3.0.0.extra", "^^9.1.0", "9.01.0"] {
                #expect(!HanlinPreparedRuntimeVersion.supportsMinimum(malformed, installed: installed))
            }
        }
        #expect(HanlinPreparedRuntimeVersion.supportsMinimum("^9.0.0", installed: "9.1.0"))
        for required in ["9.1.1", "9.10.0", "^9.999.0", "10.0.0", "9.1.0-preview.1", "8.0.0"] {
            #expect(!HanlinPreparedRuntimeVersion.supportsMinimum(required, installed: "9.1.0"))
        }
        for required in ["58.0.4", "58.1.0", "59.0.0", "58.0.0-preview.3", "57.0.0"] {
            #expect(!HanlinPreparedRuntimeVersion.supportsMinimum(required, installed: "58.0.3"))
        }
    }

    @Test func explicitBackwardBridgeCompatibilityStillRequiresCompleteStableVersions() {
        for valid in ["1.0.0", "2.0.0", "3.0.0", "~3.0.0", "3.0.0+build"] {
            #expect(HanlinPreparedRuntimeVersion.supportsMinimum(valid, installed: "3.0.0", requireSameMajor: false))
        }
        for invalid in ["", "0.0.0", "0.9.0", "3", "3.0", "3.0.0.extra", "3..0", "3.0.1", "4.0.0", "3.0.0-beta.1"] {
            #expect(!HanlinPreparedRuntimeVersion.supportsMinimum(invalid, installed: "3.0.0", requireSameMajor: false))
        }
    }

    @Test func malformedInstalledAuthorityNeverBecomesACompatibleDefault() {
        for installed in ["", "0.1.0", "latest", "9.1", "9.1.0-beta.1", "^9.1.0", "9.1.0.extra"] {
            #expect(!HanlinPreparedRuntimeVersion.supportsMinimum("9.1.0", installed: installed))
        }
    }
}
