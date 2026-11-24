# Actual application diagnostics from primary attempt 7

Executed source: fd81d602d3b25f09162a659e1e0cf0582e91a93a. These are retained failure observations; no new application run took place for this extraction.

The runtime command emitted 25 unique terminal case events (9 passed, 16 failed), then exceeded its 1,200-second budget while finalizing. OriginalRuntimes.xcresult lacks its root Info.plist, but its Staging diagnostics retain the original application standard output and system log archive.

## Established observations

- Three distinct Expo launches (Native API, Widgets, SDK-only Departure Budget) report Cannot find native module 'ExpoAsset' after initialization, followed by unhandled JavaScript exceptions. The exact target-output lines and process IDs are retained.
- SDK-only NativeScript Table Share reports Unexpected token '{' while instantiating the installed bundle.mjs. Its accessibility output also contains MiniApps unavailable and the same bootstrap error. Loader/emitter corrections still require native acceptance.
- ModularTextSearch's import action and manifest inspection ran. The embedded Node host became ready at 22:43:38.877 UTC; its retained job started at 22:43:39.085. The original UI helper waited 30 seconds for preview, then terminated the app on failure. The retained job is interrupted with zero stdout/stderr. This establishes neither a TypeScript diagnostic nor why validation had not completed. A focused completion observation is required.
- Ten Probe A cases stopped at catalog discovery. Their independently reproduced canonical-exposure and action-identity corrections are recorded in ../primary-canonical-projection-20261124/.

The actual SDK-only Expo and NativeScript validation jobs completed with zero diagnostics on this app's original SDK. Their runtime rendering results remained failures.

The terminal failure.png showed only iPad SpringBoard. Original size: 6,319,690 bytes; SHA-256 e8f0f89a2a21e102facacb64ba3502c3eb85122247de92fb68d42ea959aa3fd4. This final image cannot establish an earlier individual case's screen.

## Evidence boundary

runtime-diagnostic-extract.json preserves the target-output location, byte count, SHA-256, exact numbered excerpts, and installed Node job/ready metadata. six-failures-application.json selects application/Foundation messages for the six failed process IDs from the system log. That selection excludes other senders; the target output supplies the Expo JavaScript exception evidence. Full original logs and the unfinished bundle remain on the primary Mac. No original bundle was rewritten, and no simulator action was taken for this extraction.
