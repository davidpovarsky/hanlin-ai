# Local Mac distribution profiles

The release coordinator owns Apple account changes and installation. These helpers
do not enable capabilities, associate iCloud containers, revoke certificates,
delete profiles, install profiles, archive, or upload.

## Validate profiles that were already issued

Load the exact source entitlement plist and the privately decoded Apple CMS profile,
then call:

```python
from datetime import datetime, timezone
from audit_release_resources import evaluate_profile

evaluation = evaluate_profile(
    decoded_profile,
    source_entitlements,
    bundle_identifier,
    apple_team_id,
    distribution_certificate_der_sha256,
    datetime.now(timezone.utc),
)
```

Only `READY_RESOURCE` covers the source entitlements, exact team/application
identifier, existing certificate, expiration, and distribution profile checks.
The certificate digest is **SHA256 of the public DER certificate**, not its SHA1
keychain identity. This function has no network, installation, or signing effect.
CMS signature and Xcode signing admission remain separate existing release checks.

`$(AppIdentifierPrefix)` resolves only from a singleton alphanumeric
`ApplicationIdentifierPrefix` whose value matches the profile's complete
`application-identifier` prefix for the requested bundle. Missing, ambiguous,
malformed, or inconsistent prefixes reject the affected entitlement even when
the profile offers a broad wildcard grant. The existing exact team/bundle checks
remain unchanged. `$(TeamIdentifierPrefix)` and production APS expansion retain
their previous behavior.

A Widgets profile with `ICLOUD` enabled but an empty
`com.apple.developer.icloud-container-identifiers` array is still rejected.
The exact source container, both requested iCloud services, shared Keychain group,
app groups, HomeKit, and HealthKit remain required.

## Resolve only the main app and Widgets

After the coordinator has reconciled the actual capabilities/container association,
use the callable wrapper from the pinned helper revision:

```python
from resolve_signing_profiles import resolve_local_distribution_profiles

facts = []
profiles = resolve_local_distribution_profiles(
    distribution_certificate_der_sha256,
    private_temporary_directory,
    facts,
    source_sha=release_source_sha,
    build_number=release_build_number,
    source_root=exact_release_checkout,
)
```

The coordinator must bind `source_root` and the full lowercase 40-character
`source_sha` to its actual release source. This allows a separately pinned helper
revision to validate an unchanged application revision. Each fact records the
exact source entitlement file hash. `build_number` is an explicit positive numeric
string of at most 18 digits. Invalid or partial local naming fails before account
lookup. Names have this form:

```text
Hanlin ai App Store Mac 148901 85e374570dba
Hanlin widgets App Store Mac 148901 85e374570dba
```

The full source SHA and build number remain in `local_release_context`; the name
contains the source abbreviation. No GitHub run is inferred, populated, or changed.
Calls to `resolve_profile()` without explicit `local_source_sha` and
`local_build_number` retain the original numeric `GITHUB_RUN_ID` creation policy.

The wrapper:

1. Loads the existing main and Widgets source entitlements.
2. Matches the existing distribution certificate by public DER SHA256.
3. Reuses a compatible active App Store profile when available.
4. Creates at most one replacement candidate per role per invocation when none
   is compatible, using the same App ID and certificate.
5. Fetches that object again and applies the same complete CMS evaluation.
6. Returns only verified profiles. It never retries an uncertain creation.

An incomplete or unreadable account listing fails before replacement creation.
If creation fails or the issued profile lacks a required entitlement, reconcile
the actual Apple state before invoking again. Do not repeatedly issue profiles
while a known container association is missing. A successfully processed role may
already have a newly issued profile if a later role fails; the coordinator retains
its own account-operation receipt.

The return value is private: each profile includes `content` (CMS bytes),
`decoded` (the decoded profile), `uuid`, `profile_id`, and `bundle`. Do not log
or publish this structure. The separate `facts` list contains sanitized evaluation
results and source hashes. The wrapper does not resolve Share, Translation,
Notification Service, or MiniApps profiles.

Authentication uses the existing ProductSplit environment:
`APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, and base64 `ASC_KEY_P8`.
Keep all credential values private. The existing `install_profile()` remains
available to the coordinator after full validation and preserves existing cache
entries. Main/Widgets target overlays and export mappings must use the actual
verified profile names or UUIDs; preserve the other target mappings.

## Resolve the complete MiniApps product

The separate `resolve_local_miniapps_profiles()` wrapper takes the same arguments
and resolves the MiniApps main app plus Widgets, Share, Translation Provider, and
Notification Service. It derives that family from the original extension catalog;
it does not resolve or alter the AI main/Widgets pair. The existing
`resolve_local_distribution_profiles()` scope stays unchanged.

Use it only after the coordinator has verified the actual group and container
assignments. All five original entitlement plists are loaded before any Apple
request. Every returned profile must cover its full source entitlement dictionary,
including both App Groups. MiniApps Widgets also retains the original iCloud,
HealthKit, HomeKit, and shared Keychain requirements. A missing file, incompatible
profile, or unverified newly created profile fails the operation; the main app
profile cannot stand in for an extension.

The canonical `product_roles("miniapps")` set also drives export mapping and final
IPA signature/profile coverage. A local release must retain all five roles through
archive, export, and verification. This helper prepares profiles; it does not
establish that an archive, upload, or TestFlight processing has succeeded.

## Portable regression command

Run from `Scripts/ProductSplit` with no network or Apple credentials:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest -v \
  test_local_distribution_profiles \
  test_local_miniapps_profiles \
  test_signing_profiles.ProfileResolutionTests \
  test_signing_profiles.ProfileCacheTests
```

Coverage includes the actual source entitlement dictionaries; invalid and
identity-mismatched prefixes; wildcard masking; absent iCloud association; local
and original GitHub naming failure modes; reuse of later compatible candidates;
one creation per role; GET readback; uncertain creation; wrong certificates; and
existing cache ownership protections.
