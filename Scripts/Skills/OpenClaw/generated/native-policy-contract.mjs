// Tests/policy.test.mjs
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";

// hanlin-policy-test:case-registry
var test = (name, body) => globalThis.__hanlinPolicyCases.push({ name, body });

// Tests/policy.test.mjs
import * as original from "../generated/policy.mjs";
test("exact original policy artifact and dependency closure are pinned", async () => {
  const artifact = await readFile(new URL("../generated/policy.mjs", import.meta.url));
  const provenance = JSON.parse(await readFile(new URL("../generated/policy-provenance.json", import.meta.url)));
  assert.equal(createHash("sha256").update(artifact).digest("hex"), provenance.artifactSHA256);
  assert.deepEqual(Object.keys(original).sort(), provenance.exports);
  assert.deepEqual(provenance.runtimeImports, ["node:fs", "node:module", "node:path"]);
  assert.deepEqual(Object.keys(provenance.bundledDependencies).sort(), ["json5", "semver"]);
});
test("28 unchanged upstream policy tests run against the production artifact", async () => {
  const selection = JSON.parse(await readFile(new URL("../generated/policy-original-test-selection.json", import.meta.url)));
  const bytes = await readFile(new URL("../generated/upstream-policy-tests.mjs", import.meta.url));
  assert.equal(createHash("sha256").update(bytes).digest("hex"), selection.transformedArtifactSHA256);
  const { results } = await import("../generated/upstream-policy-tests.mjs");
  assert.equal(results.cases.length, selection.expectedTestInvocations);
  assert.ok(results.assertions >= 60);
});
test("original selection, source allowlist and disabled policy retain separate authority", () => {
  const entry = { skill: { name: "visible-name", source: "openclaw-bundled" }, metadata: { skillKey: "stable-key", always: true } };
  assert.equal(original.isSkillEntrySelected(entry, [], void 0), false);
  assert.equal(original.isSkillEntrySelected(entry, [], { "stable-key": true }), true);
  assert.equal(original.isSkillEntrySelected(entry, ["visible-name"], { "stable-key": false }), false);
  const include = (config) => original.shouldIncludeSkill({
    entry,
    config,
    platform: "darwin",
    bundledAllowlist: original.resolveBundledAllowlist(config),
    hasBin: () => {
      throw Error("Unexpected filesystem/binary probe");
    }
  });
  assert.equal(include({ skills: { allowBundled: [] } }), false);
  assert.equal(include({ skills: { allowBundled: ["stable-key"] } }), true);
  assert.equal(include({ skills: { entries: { "stable-key": { enabled: false } } } }), false);
  const workshop = { ...entry, skill: { ...entry.skill, source: "openclaw-workshop" } };
  assert.equal(original.isSkillEntrySelected(workshop, [], { "stable-key": false }), true);
});
test("original invocation policy and install preferences are data, not installation", () => {
  assert.deepEqual(
    original.resolveSkillInvocationPolicy({ "user-invocable": "false", "disable-model-invocation": "true" }),
    { userInvocable: false, disableModelInvocation: true }
  );
  assert.deepEqual(original.resolveSkillsInstallPreferences(), { preferBrew: true, nodeManager: "npm" });
  assert.deepEqual(
    original.resolveSkillsInstallPreferences({ skills: { install: { preferBrew: false, nodeManager: "pnpm" } } }),
    { preferBrew: false, nodeManager: "pnpm" }
  );
});

// Tests/policy-probe.test.mjs
import assert2 from "node:assert/strict";
import * as original2 from "../generated/policy.mjs";
import { probeOriginalPolicy } from "../policy-probe.mjs";
var input = (metadata, extra = {}) => ({
  scope: "native",
  name: "fixture",
  enabled: true,
  platform: "darwin",
  metadataPresence: metadata === void 0 ? "absent" : "present",
  frontmatter: metadata === void 0 ? {} : { metadata: JSON.stringify({ openclaw: metadata }) },
  bins: {},
  configFacts: {},
  ...extra
});
test("missing observations remain unknown but original any-bin and always short circuits stay decisive", () => {
  const missing = probeOriginalPolicy(original2, input({ requires: { bins: ["not-observed"] } }));
  assert2.equal(missing.known, false);
  assert2.equal(missing.executionVerified, false);
  assert2.deepEqual(missing.unobserved, ["bins:not-observed"]);
  const any = probeOriginalPolicy(original2, input({ requires: { anyBins: ["not-observed", "node"] } }, { bins: { node: true } }));
  assert2.equal(any.known, true);
  assert2.equal(any.rawUpstreamResult.eligible, true);
  const always = probeOriginalPolicy(original2, input({ always: true, requires: { config: ["browser.enabled"] } }));
  assert2.equal(always.known, true);
  assert2.equal(always.rawUpstreamResult.eligible, true);
  const wrongOS = probeOriginalPolicy(original2, input({ always: true, os: ["linux"] }));
  assert2.equal(wrongOS.known, true);
  assert2.equal(wrongOS.rawUpstreamResult.eligible, false);
});
test("unknown OpenClaw config cannot inherit a browser default as a verified Hanlin capability", () => {
  const value = probeOriginalPolicy(original2, input({ requires: { config: ["browser.enabled"] } }));
  assert2.equal(value.known, false);
  const observed = probeOriginalPolicy(original2, input({ requires: { config: ["browser.enabled"] } }, { configFacts: { "browser.enabled": true } }));
  assert2.equal(observed.known, true);
  assert2.equal(observed.rawUpstreamResult.eligible, true);
});
test("original disabled and degraded owner controls are isolated between inspections", () => {
  const metadata = { always: true, skillKey: "stable-key" };
  const disabled = probeOriginalPolicy(original2, input(metadata, { enabled: false }));
  assert2.equal(disabled.known, true);
  assert2.equal(disabled.rawUpstreamResult.eligible, false);
  const degraded = probeOriginalPolicy(original2, input(metadata, {
    degradedOwners: [{ ownerKind: "capability", ownerId: "skill:stable-key", state: "unavailable", paths: [], refKeys: [], reason: "secret provider failed" }]
  }));
  assert2.equal(degraded.rawUpstreamResult.eligible, false);
  assert2.equal(probeOriginalPolicy(original2, input(metadata)).rawUpstreamResult.eligible, true);
});
test("native snapshots cannot borrow iSH platform or observations", () => {
  assert2.throws(() => probeOriginalPolicy(original2, input({ always: true }, { scope: "ish" })), /input boundary/);
  const native = probeOriginalPolicy(original2, input({ requires: { bins: ["python3"] } }, { bins: { node: true } }));
  assert2.equal(native.known, false);
  assert2.equal(native.factScope, "native");
});
test("absent, invalid and future requirement shapes never become execution proof", () => {
  const absent = probeOriginalPolicy(original2, input(void 0));
  assert2.equal(absent.metadataStatus, "absent");
  assert2.equal(absent.declaredMetadata, false);
  assert2.equal(absent.executionVerified, false);
  for (const metadata of [[], { always: "yes" }, { requires: { futureGPU: [] } }, { requires: { bins: 7 } }]) {
    const value = probeOriginalPolicy(original2, input(metadata));
    assert2.equal(value.known, false);
    assert2.equal(value.metadataStatus, "unsupported");
  }
  const invalid = probeOriginalPolicy(original2, input({}, { frontmatter: { metadata: "not-json5" } }));
  assert2.equal(invalid.metadataStatus, "unsupported");
});
test("original JSON5, CSV normalization and install-hint rejection survive the typed boundary", () => {
  const value = probeOriginalPolicy(original2, input({}, {
    frontmatter: { metadata: "{openclaw:{requires:{bins:'node'},install:[{kind:'node',package:'file:../escape'},{kind:'node',package:'@scope/ok@1.2.3'}]}}" },
    bins: { node: true }
  }));
  assert2.equal(value.metadataStatus, "supported");
  assert2.equal(value.rawUpstreamResult.eligible, true);
  assert2.deepEqual(value.installHints, [{ kind: "node", package: "@scope/ok@1.2.3" }]);
});
test("rechecking actual snapshots observes both installation and removal without a stale eligibility cache", () => {
  const params = input({ requires: { bins: ["tool"] } }, { bins: { tool: false } });
  assert2.equal(probeOriginalPolicy(original2, params).rawUpstreamResult.eligible, false);
  params.bins.tool = true;
  assert2.equal(probeOriginalPolicy(original2, params).rawUpstreamResult.eligible, true);
  params.bins.tool = false;
  assert2.equal(probeOriginalPolicy(original2, params).rawUpstreamResult.eligible, false);
});
