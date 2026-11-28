#!/usr/bin/env python3
"""Generate a deterministic source inventory for the Hanlin contract audit.

This is a static indexer, not a Swift or TypeScript compiler. Its output keeps
lexical evidence separate from the audit's manually verified conclusions.
"""

from __future__ import annotations

import json
import re
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUTPUT_ROOT = ROOT / "docs" / "hanlin-platform" / "contract-audit"

DECLARATION_RE = re.compile(
    r"^\s*(?P<prefix>(?:(?:@[A-Za-z_][\w.]*(?:\([^)]*\))?|"
    r"public|package|internal|fileprivate|private|open|final|indirect|"
    r"nonisolated|nonisolated\(unsafe\)|static|class)\s+)*)"
    r"(?P<kind>struct|enum|protocol|actor|class|typealias)\s+"
    r"(?P<name>[A-Za-z_][A-Za-z0-9_]*)"
)
IDENTIFIER_RE = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")

KNOWN_OVERLAPS: dict[str, list[str]] = {
    "HanlinAppDescriptor": ["NativeAppManifest", "Scripting script.json metadata"],
    "NativeAppManifest": ["HanlinAppDescriptor", "Scripting script.json metadata"],
    "NativeAppModule": ["HanlinAppImplementation", "Hanlin entry descriptors"],
    "NativeAppRoute": ["HanlinRouteDescriptor"],
    "HanlinRouteDescriptor": ["NativeAppRoute"],
    "NativeAppAction": ["HanlinActionDescriptor"],
    "HanlinActionDescriptor": ["NativeAppAction"],
    "NativeCapabilityID": ["HanlinCapabilityID", "HanlinCapabilityDeclaration"],
    "NativeCapabilityRequest": ["HanlinCapabilityDeclaration", "missing platform permission request"],
    "NativeCapabilityStatus": ["HanlinPermissionDecisionID", "missing platform grant/decision"],
    "NativeCapabilityRegistry": ["missing platform policy/permission broker"],
    "HanlinCapabilityDeclaration": ["NativeCapabilityRequest", "Scripting permission declarations"],
    "NativeTool": ["HanlinToolDescriptor"],
    "NativeToolCatalogEntry": ["HanlinToolDescriptor", "MCPToolDescriptor"],
    "MCPToolDescriptor": ["HanlinToolDescriptor", "NativeToolCatalogEntry"],
    "HanlinToolDescriptor": ["NativeTool", "NativeToolCatalogEntry", "MCPToolDescriptor"],
    "NativeToolCatalog": ["MCPToolCatalog", "missing unified platform catalog"],
    "MCPToolCatalog": ["NativeToolCatalog", "missing unified platform catalog"],
    "NativeToolResult": ["MCP tool result", "missing platform tool result"],
    "NativeUIBlock": ["Hanlin tool presentation metadata", "AgentActivity result presentation"],
    "RuntimeJSONValue": ["HanlinValue", "MCP SDK Value"],
    "HanlinValue": ["RuntimeJSONValue", "MCP SDK Value"],
    "NativeToolSchema": ["HanlinJSONSchema", "MCP input schema JSON"],
    "HanlinJSONSchema": ["NativeToolSchema", "MCP input schema JSON"],
    "RuntimeCoreError": ["MCPError", "HanlinPlatformError"],
    "MCPError": ["RuntimeCoreError", "HanlinPlatformError"],
    "HanlinPlatformError": ["RuntimeCoreError", "MCPError"],
    "MCPServerDescriptor": ["missing platform installed-package/provider record"],
    "RuntimeExecutionRequest": ["HanlinScriptEnvelope", "missing platform execution request"],
    "RuntimeExecutionResult": ["missing platform execution result"],
    "AgentToolCall": ["NativeTool invocation", "MCP tool call", "missing platform invocation"],
    "AgentEvent": ["HanlinScriptMessageKind", "MCP/runtime lifecycle events"],
    "AgentRun": ["missing platform activity/audit contract"],
    "NativeAppSession": ["HanlinSessionID", "missing platform app-session contract"],
    "HanlinSessionID": ["NativeAppSession", "missing platform session contract"],
}


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def subsystem_for(path: str) -> str:
    mappings = (
        ("Packages/HanlinPlatform", "HanlinPlatformContracts"),
        ("AI_HLY/NativeAppPlatform", "NativeAppPlatform"),
        ("AI_HLY/NativeAgentExtensions", "NativeAgentExtensions"),
        ("AI_HLY/Downstream/MCP", "MCP"),
        ("AI_HLY/Downstream/RuntimeCore", "RuntimeCore"),
        ("AI_HLY/Downstream/AgentActivity", "AgentActivity"),
        ("AI_HLY/Downstream/AgentDiagnostics", "AgentDiagnostics"),
        ("AI_HLY/Services/ChatServices", "Chat/tool integration"),
        ("AI_HLY/Services/ModelServices", "Model services"),
        ("AI_HLY/Model", "App persistence models"),
        ("AI_HLY", "AI_HLY app/UI"),
        ("Packages/IOSSystemLite", "IOSSystemLite"),
    )
    for prefix, subsystem in mappings:
        if path.startswith(prefix):
            return subsystem
    return "Other Swift"


def target_for(path: str) -> str:
    if path.startswith("Packages/HanlinPlatform/Tests/"):
        return "HanlinPlatformContractsTests"
    if path.startswith("Packages/HanlinPlatform/Sources/"):
        return "HanlinPlatformContracts"
    if path.startswith("Packages/HanlinPlatform/"):
        return "HanlinPlatform package manifest"
    if path.startswith("Packages/IOSSystemLite/Tests/"):
        return "IOSSystemLite tests"
    if path.startswith("Packages/IOSSystemLite/"):
        return "IOSSystemLite package (product linked to AI_Hanlin)"
    if path.startswith("AI_HLY/"):
        return "AI_Hanlin (filesystem-synchronized group)"
    return "Repository tooling/reference"


def strip_comments_and_strings(line: str, in_block_comment: bool) -> tuple[str, bool]:
    result: list[str] = []
    index = 0
    quote: str | None = None
    escaped = False
    while index < len(line):
        char = line[index]
        nxt = line[index + 1] if index + 1 < len(line) else ""
        if in_block_comment:
            if char == "*" and nxt == "/":
                in_block_comment = False
                result.extend("  ")
                index += 2
            else:
                result.append(" ")
                index += 1
            continue
        if quote is not None:
            result.append(" ")
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            index += 1
            continue
        if char == "/" and nxt == "*":
            in_block_comment = True
            result.extend("  ")
            index += 2
        elif char == "/" and nxt == "/":
            result.extend(" " * (len(line) - index))
            break
        elif char in {'"', "'"}:
            quote = char
            result.append(" ")
            index += 1
        else:
            result.append(char)
            index += 1
    return "".join(result), in_block_comment


def sanitized_lines(lines: list[str]) -> list[str]:
    output: list[str] = []
    in_block = False
    for line in lines:
        cleaned, in_block = strip_comments_and_strings(line, in_block)
        output.append(cleaned)
    return output


def declaration_end(clean: list[str], start: int, kind: str) -> int:
    if kind == "typealias":
        return start
    depth = 0
    found_open = False
    for index in range(start, len(clean)):
        for char in clean[index]:
            if char == "{":
                depth += 1
                found_open = True
            elif char == "}" and found_open:
                depth -= 1
                if depth == 0:
                    return index
        if not found_open and index > start + 20:
            return start
    return len(clean) - 1


def signature_for(lines: list[str], start: int, end: int, kind: str) -> str:
    if kind == "typealias":
        return lines[start].strip()
    pieces: list[str] = []
    for index in range(start, min(end + 1, start + 21)):
        piece = lines[index].strip()
        pieces.append(piece.split("{", 1)[0].strip())
        if "{" in lines[index]:
            break
    return " ".join(piece for piece in pieces if piece)


def conformances_from(signature: str, name: str) -> list[str]:
    after_name = signature.split(name, 1)[-1]
    if ":" not in after_name:
        return []
    clause = after_name.split(":", 1)[1]
    clause = clause.split(" where ", 1)[0]
    return [
        item.strip()
        for item in clause.split(",")
        if item.strip() and not item.strip().startswith("(")
    ]


def direct_members(clean: list[str], lines: list[str], start: int, end: int) -> list[str]:
    members: list[str] = []
    depth = 0
    opened = False
    member_re = re.compile(
        r"^\s*(?:(?:public|package|internal|fileprivate|private|open|final|"
        r"static|class|mutating|nonmutating|nonisolated|required|convenience|"
        r"override)\s+)*(?:let|var|case|func|init|subscript|associatedtype)\b"
    )
    for index in range(start, end + 1):
        line = clean[index]
        before = depth
        depth += line.count("{") - line.count("}")
        if "{" in line:
            opened = True
        direct_depth = before if index > start else depth
        if opened and direct_depth == 1 and member_re.match(line):
            value = lines[index].strip()
            if value and value not in members:
                members.append(value)
    return members


def role_for(path: str, name: str, kind: str, conformances: list[str]) -> str:
    lower = f"{path} {name}".lower()
    if "/Tests/" in path or path.endswith("Tests.swift") or "acceptance" in lower:
        return "Test/validation model"
    if any(token in lower for token in ("view", "renderer", "style", "presentation")):
        return "UI model"
    if any(token in lower for token in ("store", "record", "persist", "manifestdocument")):
        return "Persistence model"
    if any(token in lower for token in ("transport", "envelope", "wire", "request", "response")):
        return "Wire/boundary model"
    if any(token in lower for token in ("service", "broker", "controller", "manager")):
        return "Runtime/service implementation"
    if any(token in lower for token in ("descriptor", "manifest", "identifier", "version", "schema")):
        return "Canonical candidate" if path.startswith("Packages/HanlinPlatform/Sources") else "Domain contract"
    if kind == "protocol":
        return "Service/behavior contract"
    if "Codable" in conformances or "Sendable" in conformances:
        return "Domain/transport model"
    return "Implementation model"


def persistence_for(path: str, name: str, source: str, conformances: list[str]) -> str:
    lower = f"{path} {name} {source}".lower()
    if "@model" in lower or "swiftdata" in lower:
        return "SwiftData"
    if "userdefaults" in lower:
        return "UserDefaults"
    if "keychain" in lower or "secretstore" in lower:
        return "Keychain"
    if any(token in lower for token in ("registrystore", "jsonstore", "persistence", "installedpackagemanifest")):
        return "JSON/file store"
    if "Codable" in conformances:
        return "Codable; persistence use requires consumer evidence"
    return "None found in declaration"


def wire_for(path: str, name: str, role: str, conformances: list[str]) -> str:
    lower = f"{path} {name}".lower()
    if any(token in lower for token in ("wire", "envelope", "transport", "toolcall", "executionrequest", "executionresult")):
        return "yes"
    if role == "Wire/boundary model":
        return "boundary candidate"
    if "Codable" in conformances and any(
        path.startswith(prefix)
        for prefix in (
            "Packages/HanlinPlatform/Sources",
            "AI_HLY/Downstream/MCP",
            "AI_HLY/Downstream/RuntimeCore",
        )
    ):
        return "Codable boundary candidate; verify call site"
    return "no direct boundary evidence"


def live_status(path: str, occurrence_count: int) -> str:
    if "/Tests/" in path or path.endswith("Tests.swift"):
        return "Tests only"
    if path.startswith("Packages/HanlinPlatform/Sources/"):
        return "Package-only and unlinked"
    if path.startswith("Packages/HanlinPlatform/"):
        return "Package manifest"
    if path.startswith("AI_HLY/"):
        if occurrence_count <= 1:
            return "Compiled; no external token consumer found"
        return "Compiled in AI_Hanlin"
    if path.startswith("Packages/IOSSystemLite/"):
        return "Linked package implementation"
    return "Unclear"


def build_token_index(files: list[Path]) -> tuple[dict[str, set[str]], dict[str, set[str]]]:
    consumers: dict[str, set[str]] = defaultdict(set)
    producers: dict[str, set[str]] = defaultdict(set)
    constructor_re = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*\(")
    for path in files:
        text = path.read_text(encoding="utf-8", errors="replace")
        rel = relative(path)
        for token in set(IDENTIFIER_RE.findall(text)):
            consumers[token].add(rel)
        for token in set(constructor_re.findall(text)):
            producers[token].add(rel)
    return consumers, producers


def swift_entries() -> tuple[list[dict[str, object]], int]:
    files = sorted(
        path for path in ROOT.rglob("*.swift")
        if ".build" not in path.parts and "DerivedData" not in path.parts
    )
    consumers, producers = build_token_index(files)
    entries: list[dict[str, object]] = []
    for path in files:
        rel = relative(path)
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        clean = sanitized_lines(lines)
        for start, line in enumerate(clean):
            match = DECLARATION_RE.match(line)
            if not match:
                continue
            kind = match.group("kind")
            name = match.group("name")
            end = declaration_end(clean, start, kind)
            signature = signature_for(lines, start, end, kind)
            conformances = conformances_from(signature, name)
            source = "\n".join(lines[start:end + 1])
            consumer_paths = sorted(consumers.get(name, set()) - {rel})
            producer_paths = sorted(producers.get(name, set()) - {rel})
            role = role_for(rel, name, kind, conformances)
            entry = {
                "name": name,
                "kind": kind,
                "path": rel,
                "lineStart": start + 1,
                "lineEnd": end + 1,
                "subsystem": subsystem_for(rel),
                "target": target_for(rel),
                "appTargetInclusion": rel.startswith("AI_HLY/"),
                "swiftPackageInclusion": rel.startswith("Packages/"),
                "liveStatus": "",
                "role": role,
                "persistence": persistence_for(rel, name, source, conformances),
                "wireBoundary": wire_for(rel, name, role, conformances),
                "consumers": consumer_paths[:20],
                "producers": producer_paths[:20],
                "overlaps": KNOWN_OVERLAPS.get(name, []),
                "notes": "Lexical inventory; semantic conclusions require the cited source and call-site review.",
                "signature": signature,
                "conformances": conformances,
                "members": direct_members(clean, lines, start, end),
                "codable": any(value in {"Codable", "Encodable", "Decodable"} for value in conformances),
                "sendable": "Sendable" in conformances or kind == "actor",
                "actorIsolation": "@MainActor" if "@MainActor" in signature or "@MainActor" in "\n".join(lines[max(0, start - 2):start]) else ("actor" if kind == "actor" else "not explicit"),
                "occurrenceFiles": len(consumers.get(name, set())),
            }
            entry["liveStatus"] = live_status(rel, int(entry["occurrenceFiles"]))
            entries.append(entry)
    return entries, len(files)


def scripting_entries() -> list[dict[str, object]]:
    generated = ROOT / "Reference" / "ScriptingCompatibility" / "Generated"
    inventory = json.loads((generated / "api-inventory.json").read_text(encoding="utf-8"))
    symbol_index = json.loads((generated / "symbol-index.json").read_text(encoding="utf-8"))
    indexed = {
        (item["declarationFile"], item["line"], item["referenceSymbol"]): item
        for item in symbol_index["symbols"]
    }
    example_files = sorted(
        path for path in (ROOT / "Reference" / "ScriptingCompatibility" / "Original").rglob("*")
        if path.is_file() and path.suffix.lower() in {".ts", ".tsx"}
        and "Types" not in path.parts
    )
    example_consumers, example_producers = build_token_index(example_files)
    entries: list[dict[str, object]] = []
    for symbol in inventory["symbols"]:
        name = symbol["name"]
        declaration_file = symbol["declarationFile"]
        line = symbol["line"]
        details = indexed.get((declaration_file, line, name), {})
        path = f"Reference/ScriptingCompatibility/Original/Types/{declaration_file}"
        documents = [
            f"Reference/ScriptingCompatibility/Original/Documentation/{item}"
            for item in details.get("documents", [])
        ]
        examples = sorted(example_consumers.get(name, set()))
        producers = sorted(example_producers.get(name, set()))
        entries.append({
            "name": name,
            "kind": symbol["category"],
            "path": path,
            "lineStart": line,
            "lineEnd": line,
            "subsystem": "Scripting reference",
            "target": "Reference only; not packaged or compiled by AI_Hanlin",
            "appTargetInclusion": False,
            "swiftPackageInclusion": False,
            "liveStatus": "Documentation/reference only",
            "role": "Scripting-reference-only",
            "persistence": "Reference declaration; runtime behavior not proven",
            "wireBoundary": "Reference declaration; runtime behavior not proven",
            "consumers": (documents + examples)[:30],
            "producers": producers[:20],
            "overlaps": [],
            "notes": "Phase 0 lexer obligation. Declaration presence and examples do not prove Hanlin runtime support.",
            "signature": details.get("signature", ""),
            "conformances": [],
            "members": [],
            "codable": False,
            "sendable": False,
            "actorIsolation": "TypeScript reference",
            "occurrenceFiles": len(set(documents + examples)),
        })
    return entries


def markdown_table(entries: list[dict[str, object]]) -> str:
    rows = [
        "| Declaration | Kind | Evidence | Target/live status | Role | Codable / Sendable | Persistence / wire | Producers / consumers | Known overlaps |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for entry in entries:
        evidence = f"`{entry['path']}:{entry['lineStart']}-{entry['lineEnd']}`"
        conformances = ", ".join(entry.get("conformances", [])) or "—"
        traits = f"{conformances}; Codable={entry['codable']}; Sendable={entry['sendable']}"
        boundary = f"{entry['persistence']}; wire={entry['wireBoundary']}"
        producers = ", ".join(f"`{item}`" for item in entry["producers"][:3]) or "—"
        consumers = ", ".join(f"`{item}`" for item in entry["consumers"][:3]) or "—"
        flow = f"P: {producers}<br>C: {consumers}"
        overlaps = ", ".join(f"`{item}`" for item in entry["overlaps"]) or "—"
        values = [
            f"`{entry['name']}`",
            str(entry["kind"]),
            evidence,
            f"{entry['target']}<br>{entry['liveStatus']}",
            str(entry["role"]),
            traits,
            boundary,
            flow,
            overlaps,
        ]
        rows.append("| " + " | ".join(value.replace("|", "\\|").replace("\n", " ") for value in values) + " |")
    return "\n".join(rows)


def write_outputs(swift: list[dict[str, object]], scripting: list[dict[str, object]], swift_file_count: int) -> None:
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    all_entries = swift + scripting
    subsystem_counts = Counter(str(entry["subsystem"]) for entry in all_entries)
    live_counts = Counter(str(entry["liveStatus"]) for entry in all_entries)
    document = {
        "schemaVersion": 1,
        "generatedFromHEAD": "da0929110903c83e9314ccd29d14d6d8be987d1a",
        "generator": "Scripts/Audit/generate_contract_inventory.py",
        "method": "Lexical declaration and token-use index; not compiler-backed call-graph analysis.",
        "summary": {
            "swiftFilesScanned": swift_file_count,
            "swiftDeclarations": len(swift),
            "scriptingReferenceSymbols": len(scripting),
            "totalDeclarations": len(all_entries),
            "subsystems": dict(sorted(subsystem_counts.items())),
            "liveStatuses": dict(sorted(live_counts.items())),
        },
        "declarations": all_entries,
    }
    (OUTPUT_ROOT / "contract-inventory.json").write_text(
        json.dumps(document, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
        newline="\n",
    )

    swift_by_subsystem: dict[str, list[dict[str, object]]] = defaultdict(list)
    for entry in swift:
        swift_by_subsystem[str(entry["subsystem"])].append(entry)
    sections = [
        "# Contract inventory",
        "",
        "> Generated lexical evidence supplemented by the narrative audit. Token occurrence is not a compiler call graph; every dead-code or ownership conclusion in the report is separately qualified.",
        "",
        "## Coverage",
        "",
        f"- Swift files scanned: **{swift_file_count}**.",
        f"- Swift declarations indexed: **{len(swift)}**.",
        f"- Scripting reference symbols indexed: **{len(scripting)}** from all five declaration files.",
        f"- Total declaration records: **{len(all_entries)}**.",
        "- All paths and line ranges refer to HEAD `da0929110903c83e9314ccd29d14d6d8be987d1a`.",
        "",
    ]
    for subsystem in sorted(swift_by_subsystem):
        entries = sorted(swift_by_subsystem[subsystem], key=lambda item: (str(item["path"]), int(item["lineStart"])))
        sections.extend([f"## {subsystem}", "", markdown_table(entries), ""])

    scripting_counts = Counter(str(entry["kind"]) for entry in scripting)
    scripting_file_counts = Counter(Path(str(entry["path"])).name for entry in scripting)
    sections.extend([
        "## Scripting reference declarations",
        "",
        "These are reference obligations, not Hanlin runtime claims. The machine-readable inventory contains one record for each symbol with declaration line, documentation/example references, and explicit reference-only status.",
        "",
        "### Counts by declaration file",
        "",
        *[f"- `{name}`: {count}" for name, count in sorted(scripting_file_counts.items())],
        "",
        "### Counts by declaration kind",
        "",
        *[f"- `{name}`: {count}" for name, count in sorted(scripting_counts.items())],
        "",
        "### Declaration-by-declaration index",
        "",
        markdown_table(sorted(scripting, key=lambda item: (str(item["path"]), int(item["lineStart"]), str(item["name"])))),
        "",
    ])
    (OUTPUT_ROOT / "CONTRACT_INVENTORY.md").write_text(
        "\n".join(sections), encoding="utf-8", newline="\n"
    )


def main() -> None:
    swift, swift_file_count = swift_entries()
    scripting = scripting_entries()
    write_outputs(swift, scripting, swift_file_count)
    print(json.dumps({
        "swiftFilesScanned": swift_file_count,
        "swiftDeclarations": len(swift),
        "scriptingReferenceSymbols": len(scripting),
        "totalDeclarations": len(swift) + len(scripting),
    }, indent=2))


if __name__ == "__main__":
    main()
