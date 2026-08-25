import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import vm from "node:vm";

const repositoryRoot = path.resolve(import.meta.dirname, "../../..");
const swift = fs.readFileSync(path.join(
  repositoryRoot,
  "AI_HLY/Downstream/Scripting/HanlinScriptValueBridge.swift",
), "utf8");
const marker = `static let bootstrap = #${'"'.repeat(3)}`;
const start = swift.indexOf(marker) + marker.length;
const bootstrap = swift.slice(start, swift.indexOf(`${'"'.repeat(3)}#`, start));

function canonicalObject(value) {
  return {
    type: "object",
    value: Object.fromEntries(Object.entries(value).map(([key, member]) => [key, canonical(member)])),
  };
}

function canonical(value) {
  if (value === null) return { type: "null" };
  if (typeof value === "boolean") return { type: "bool", value };
  if (typeof value === "string") return { type: "string", value };
  if (typeof value === "bigint") return { type: "integer", value: String(value) };
  if (Array.isArray(value)) return { type: "array", value: value.map(canonical) };
  return canonicalObject(value);
}

test("AssistantTool maintains per-call state and replaces progress reports by id", async () => {
  const context = vm.createContext({});
  vm.runInContext(bootstrap, context);
  vm.runInContext(`
    AssistantTool.registerExecuteTool(async params => {
      AssistantTool.setState("input", params.value);
      AssistantTool.report("starting", "progress");
      AssistantTool.report("finished", "progress");
      return {
        success: AssistantTool.getState("input") === params.value,
        message: __hanlinToolReports()[0].message
      };
    });
  `, context);
  const input = canonicalObject({
    __hanlinToolIndex: 0n,
    parameters: { value: "round-trip" },
  });
  const output = JSON.parse(await context.__hanlinInvoke(JSON.stringify(input)));
  assert.deepEqual(output.value.success, { type: "bool", value: true });
  assert.deepEqual(output.value.message, { type: "string", value: "finished" });
});

test("AssistantTool cancellation is idempotent and clears onCancel after use", () => {
  const context = vm.createContext({});
  vm.runInContext(bootstrap, context);
  vm.runInContext(`
    globalThis.cancelCount = 0;
    AssistantTool.onCancel = () => { cancelCount += 1; return "cancelled"; };
  `, context);
  assert.equal(context.__hanlinCancelCurrent(), "cancelled");
  assert.equal(context.__hanlinCancelCurrent(), null);
  assert.equal(context.cancelCount, 1);
  assert.equal(context.AssistantTool.isCancelled, true);
  assert.equal(context.AssistantTool.onCancel, null);
});
