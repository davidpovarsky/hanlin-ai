import { describe, expect, it, test, mockProcessPlatform, expectDefined, results } from "../Tests/policy-upstream-shim.mjs";
import { applyOpenClawManifestInstallCommonFields, parseFrontmatterBool, parseOpenClawManifestInstallBase, resolveOpenClawManifestBlock, resolveOpenClawManifestInstall, resolveOpenClawManifestOs, resolveOpenClawManifestRequires, resolveSkillManifestMetadata, evaluateRuntimeEligibility, isConfigPathTruthyWithDefaults, shouldIncludeSkill, setActiveDegradedSecretOwners } from "./policy.mjs";
describe("shared/frontmatter", () => {
  test("parseFrontmatterBool respects explicit values and fallback", () => {
    expect(parseFrontmatterBool("true", false)).toBe(true);
    expect(parseFrontmatterBool("false", true)).toBe(false);
    expect(parseFrontmatterBool(void 0, true)).toBe(true);
    expect(parseFrontmatterBool("maybe", false)).toBe(false);
  });
  test("resolveOpenClawManifestBlock returns undefined for invalid input", () => {
    expect(resolveOpenClawManifestBlock({ frontmatter: {} })).toBeUndefined();
    expect(
      resolveOpenClawManifestBlock({ frontmatter: { metadata: "not-json5" } })
    ).toBeUndefined();
    expect(resolveOpenClawManifestBlock({ frontmatter: { metadata: "123" } })).toBeUndefined();
    expect(resolveOpenClawManifestBlock({ frontmatter: { metadata: "[]" } })).toBeUndefined();
    expect(
      resolveOpenClawManifestBlock({ frontmatter: { metadata: "{ nope: { a: 1 } }" } })
    ).toBeUndefined();
  });
  it("normalizes manifest requirement and os lists", () => {
    expect(
      resolveOpenClawManifestRequires({
        requires: {
          bins: "bun, node",
          anyBins: [" ffmpeg ", ""],
          env: ["OPENCLAW_TOKEN", " OPENCLAW_URL "],
          config: null
        }
      })
    ).toEqual({
      bins: ["bun", "node"],
      anyBins: ["ffmpeg"],
      env: ["OPENCLAW_TOKEN", "OPENCLAW_URL"],
      config: []
    });
    expect(resolveOpenClawManifestRequires({})).toBeUndefined();
    expect(resolveOpenClawManifestOs({ os: [" darwin ", "linux", ""] })).toEqual([
      "darwin",
      "linux"
    ]);
  });
  it("parses and applies install common fields", () => {
    const parsed = parseOpenClawManifestInstallBase(
      {
        type: " Brew ",
        id: "brew.git",
        label: "Git",
        bins: [" git ", "git"]
      },
      ["brew", "npm"]
    );
    expect(parsed).toEqual({
      raw: {
        type: " Brew ",
        id: "brew.git",
        label: "Git",
        bins: [" git ", "git"]
      },
      kind: "brew",
      id: "brew.git",
      label: "Git",
      bins: ["git", "git"]
    });
    expect(parseOpenClawManifestInstallBase({ kind: "bad" }, ["brew"])).toBeUndefined();
    expect(
      applyOpenClawManifestInstallCommonFields({ extra: true }, expectDefined(parsed, "manifest install base"))
    ).toEqual({
      extra: true,
      id: "brew.git",
      label: "Git",
      bins: ["git", "git"]
    });
  });
  it("prefers explicit kind, ignores invalid common fields, and leaves missing ones untouched", () => {
    const parsed = parseOpenClawManifestInstallBase(
      {
        kind: " npm ",
        type: "brew",
        id: 42,
        label: null,
        bins: [" ", ""]
      },
      ["brew", "npm"]
    );
    expect(parsed).toEqual({
      raw: {
        kind: " npm ",
        type: "brew",
        id: 42,
        label: null,
        bins: [" ", ""]
      },
      kind: "npm"
    });
    expect(
      applyOpenClawManifestInstallCommonFields(
        { id: "keep", label: "Keep", bins: ["bun"] },
        parsed
      )
    ).toEqual({
      id: "keep",
      label: "Keep",
      bins: ["bun"]
    });
  });
  it("maps install entries through the parser and filters rejected specs", () => {
    expect(
      resolveOpenClawManifestInstall(
        {
          install: [{ id: "keep" }, { id: "drop" }, "bad"]
        },
        (entry) => {
          if (typeof entry === "object" && entry !== null && entry.id === "keep") {
            return { id: "keep" };
          }
          return void 0;
        }
      )
    ).toEqual([{ id: "keep" }]);
  });
});
describe("resolveSkillManifestMetadata install validation", () => {
  function resolveInstall(frontmatter) {
    return resolveSkillManifestMetadata(frontmatter)?.install;
  }
  it("accepts safe install specs", () => {
    const install = resolveInstall({
      metadata: '{"openclaw":{"install":[{"kind":"brew","formula":"python@3.12"},{"kind":"node","package":"@scope/pkg@1.2.3"},{"kind":"go","module":"example.com/tool/cmd@v1.2.3"},{"kind":"uv","package":"uvicorn[standard]==0.31.0"},{"kind":"download","url":"https://example.com/tool.tar.gz"}]}}'
    });
    expect(install).toEqual([
      { kind: "brew", formula: "python@3.12" },
      { kind: "node", package: "@scope/pkg@1.2.3" },
      { kind: "go", module: "example.com/tool/cmd@v1.2.3" },
      { kind: "uv", package: "uvicorn[standard]==0.31.0" },
      { kind: "download", url: "https://example.com/tool.tar.gz" }
    ]);
  });
  it("drops unsafe brew formula values", () => {
    const install = resolveInstall({
      metadata: '{"openclaw":{"install":[{"kind":"brew","formula":"wget --HEAD"}]}}'
    });
    expect(install).toBeUndefined();
  });
  it("drops unsafe npm package specs for node installers", () => {
    const install = resolveInstall({
      metadata: '{"openclaw":{"install":[{"kind":"node","package":"file:../malicious"}]}}'
    });
    expect(install).toBeUndefined();
  });
  it("drops unsafe go module specs", () => {
    const install = resolveInstall({
      metadata: '{"openclaw":{"install":[{"kind":"go","module":"https://evil.example/mod"}]}}'
    });
    expect(install).toBeUndefined();
  });
  it("drops unsafe download urls", () => {
    const install = resolveInstall({
      metadata: '{"openclaw":{"install":[{"kind":"download","url":"file:///tmp/payload.tgz"}]}}'
    });
    expect(install).toBeUndefined();
  });
  it("normalizes a download installer's optional SHA-256 digest", () => {
    const sha256 = "a".repeat(64);
    const install = resolveInstall({
      metadata: JSON.stringify({
        openclaw: {
          install: [
            {
              kind: "download",
              url: "https://example.com/runtime.tar.bz2",
              sha256: ` ${sha256.toUpperCase()} `
            }
          ]
        }
      })
    });
    expect(install).toEqual([
      { kind: "download", url: "https://example.com/runtime.tar.bz2", sha256 }
    ]);
  });
  it.each(["g".repeat(64), 123])(
    "drops a download installer declaring an invalid SHA-256 digest (%j)",
    (sha256) => {
      const install = resolveInstall({
        metadata: JSON.stringify({
          openclaw: {
            install: [{ kind: "download", url: "https://example.com/runtime.tar.bz2", sha256 }]
          }
        })
      });
      expect(install).toBeUndefined();
    }
  );
});
describe("config-eval helpers", () => {
  it("normalizes truthy values across primitive types", () => {
    for (const [value, expected] of [
      [void 0, false],
      [null, false],
      [false, false],
      [true, true],
      [0, false],
      [1, true],
      ["   ", false],
      [" ok ", true],
      [{}, true]
    ]) {
      expect(isConfigPathTruthyWithDefaults({ value }, "value", {})).toBe(expected);
    }
  });
  it("resolves nested config paths and missing branches safely", () => {
    const config = {
      browser: {
        enabled: true,
        nested: {
          count: 1
        }
      }
    };
    expect(isConfigPathTruthyWithDefaults(config, "browser.enabled", {})).toBe(true);
    expect(isConfigPathTruthyWithDefaults(config, ".browser..nested.count.", {})).toBe(true);
    expect(isConfigPathTruthyWithDefaults(config, "browser.missing.value", {})).toBe(false);
    expect(isConfigPathTruthyWithDefaults("not-an-object", "browser.enabled", {})).toBe(false);
  });
  it("blocks prototype keys while resolving config paths", () => {
    const config = {
      safe: {
        enabled: true
      }
    };
    expect(isConfigPathTruthyWithDefaults(config, "safe.enabled", {})).toBe(true);
    expect(isConfigPathTruthyWithDefaults(config, "__proto__", {})).toBe(false);
    expect(isConfigPathTruthyWithDefaults(config, "constructor.name", {})).toBe(false);
    expect(isConfigPathTruthyWithDefaults(config, "prototype.polluted", {})).toBe(false);
  });
  it("uses defaults only when config paths are unresolved", () => {
    const config = {
      browser: {
        enabled: false
      }
    };
    expect(
      isConfigPathTruthyWithDefaults(config, "browser.enabled", { "browser.enabled": true })
    ).toBe(false);
    expect(
      isConfigPathTruthyWithDefaults(config, "browser.missing", { "browser.missing": true })
    ).toBe(true);
    expect(isConfigPathTruthyWithDefaults(config, "browser.other", {})).toBe(false);
  });
  it("does not use inherited defaults for blocked config paths", () => {
    expect(isConfigPathTruthyWithDefaults({}, "constructor", {})).toBe(false);
    expect(isConfigPathTruthyWithDefaults({}, "__proto__.enabled", {})).toBe(false);
    expect(isConfigPathTruthyWithDefaults({}, "prototype.enabled", {})).toBe(false);
  });
  it("returns the active runtime platform", () => {
    mockProcessPlatform("darwin");
    expect(
      evaluateRuntimeEligibility({
        os: ["darwin"],
        hasBin: () => true,
        hasEnv: () => true,
        isConfigPathTruthy: () => true
      })
    ).toBe(true);
  });
});
describe("runtime requirements through eligibility", () => {
  it("accepts remote bins and remote any-bin matches", () => {
    const result = evaluateRuntimeEligibility({
      requires: {
        bins: ["node"],
        anyBins: ["bun", "deno"],
        env: ["OPENAI_API_KEY"],
        config: ["browser.enabled"]
      },
      hasBin: () => false,
      hasRemoteBin: (bin) => bin === "node",
      hasAnyRemoteBin: (bins) => bins.includes("deno"),
      hasEnv: (name) => name === "OPENAI_API_KEY",
      isConfigPathTruthy: (pathValue) => pathValue === "browser.enabled"
    });
    expect(result).toBe(true);
  });
  it("rejects when any required runtime check is still unsatisfied", () => {
    expect(
      evaluateRuntimeEligibility({
        requires: { bins: ["node"] },
        hasBin: () => false,
        hasEnv: () => true,
        isConfigPathTruthy: () => true
      })
    ).toBe(false);
    expect(
      evaluateRuntimeEligibility({
        requires: { anyBins: ["bun", "node"] },
        hasBin: () => false,
        hasAnyRemoteBin: () => false,
        hasEnv: () => true,
        isConfigPathTruthy: () => true
      })
    ).toBe(false);
  });
});
describe("evaluateRuntimeEligibility", () => {
  it("rejects entries when required OS does not match local or remote", () => {
    const result = evaluateRuntimeEligibility({
      os: ["definitely-not-a-runtime-platform"],
      remotePlatforms: [],
      hasBin: () => true,
      hasEnv: () => true,
      isConfigPathTruthy: () => true
    });
    expect(result).toBe(false);
  });
  it("accepts entries when remote platform satisfies OS requirements", () => {
    mockProcessPlatform("darwin");
    const result = evaluateRuntimeEligibility({
      os: ["linux"],
      remotePlatforms: ["linux"],
      hasBin: () => true,
      hasEnv: () => true,
      isConfigPathTruthy: () => true
    });
    expect(result).toBe(true);
  });
  it("bypasses runtime requirements when always=true", () => {
    const result = evaluateRuntimeEligibility({
      always: true,
      requires: { env: ["OPENAI_API_KEY"] },
      hasBin: () => false,
      hasEnv: () => false,
      isConfigPathTruthy: () => false
    });
    expect(result).toBe(true);
  });
  it("evaluates runtime requirements when always is false", () => {
    const result = evaluateRuntimeEligibility({
      requires: {
        bins: ["node"],
        anyBins: ["bun", "node"],
        env: ["OPENAI_API_KEY"],
        config: ["browser.enabled"]
      },
      hasBin: (bin) => bin === "node",
      hasAnyRemoteBin: () => false,
      hasEnv: (name) => name === "OPENAI_API_KEY",
      isConfigPathTruthy: (pathLocal) => pathLocal === "browser.enabled"
    });
    expect(result).toBe(true);
  });
});
const withClearedEnv = (keys, run) => {
  const original = {};
  for (const key of keys) {
    original[key] = process.env[key];
    delete process.env[key];
  }
  try {
    return run(original);
  } finally {
    for (const key of keys) {
      const value = original[key];
      if (value === void 0) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
  }
};
function makeSkillEntry(name, metadata, description = "Needs env") {
  const baseDir = `/virtual/${name}`;
  const filePath = `${baseDir}/SKILL.md`;
  return {
    skill: {
      name,
      description,
      filePath,
      baseDir,
      source: "test",
      sourceInfo: { path: filePath, source: "test", scope: "temporary", origin: "top-level" },
      disableModelInvocation: false
    },
    frontmatter: {},
    metadata
  };
}
function rawSkillApiKeyRefConfig(skillName) {
  return {
    skills: {
      entries: {
        [skillName]: {
          apiKey: {
            source: "file",
            provider: "default",
            id: `/skills/entries/${skillName}/apiKey`
          }
        }
      }
    }
  };
}
describe("shouldIncludeSkill", () => {
  const envName = "OPENCLAW_TEST_SKILL_REQUIREMENT";
  const entry = makeSkillEntry("env-skill", {
    primaryEnv: envName,
    requires: { env: [envName] }
  });
  function shouldInclude(config) {
    return shouldIncludeSkill({ entry, config, bundledAllowlist: void 0 });
  }
  it("requires non-blank host and configured env values", () => {
    withClearedEnv([envName], () => {
      expect(shouldInclude()).toBe(false);
      process.env[envName] = "   ";
      expect(shouldInclude()).toBe(false);
      process.env[envName] = " example ";
      expect(shouldInclude()).toBe(true);
      delete process.env[envName];
      expect(
        shouldInclude({ skills: { entries: { "env-skill": { env: { [envName]: "   " } } } } })
      ).toBe(false);
      expect(
        shouldInclude({
          skills: { entries: { "env-skill": { env: { [envName]: " example " } } } }
        })
      ).toBe(true);
    });
  });
  it("excludes only the skill whose configured secret is unavailable", () => {
    setActiveDegradedSecretOwners([
      {
        ownerKind: "capability",
        ownerId: "skill:env-skill",
        state: "unavailable",
        paths: ["skills.entries.env-skill.apiKey"],
        refKeys: ["env:default:MISSING_SKILL_KEY"],
        reason: "secret provider failed"
      }
    ]);
    expect(shouldInclude(rawSkillApiKeyRefConfig("env-skill"))).toBe(false);
    expect(
      shouldIncludeSkill({
        entry: makeSkillEntry("healthy-skill", { always: true }),
        bundledAllowlist: void 0
      })
    ).toBe(true);
  });
});
export {
  results
};
