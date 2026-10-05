# Torah Photo Study — Provider Setup Guide

---

## 1. Local Apple Vision OCR

- **Engine:** `VNRecognizeTextRequest` (Apple Vision Framework).
- **Supported Platforms:** iOS 17+, macOS 14+.
- **Configuration:**
  - Recognition Level: `.accurate`
  - Recognition Languages: `["he", "en"]`
  - Uses Language Correction: `true`
  - Region of Interest: Dynamically mapped to normalized `OCRRegion` coordinates `(x, y, width, height)` in `[0.0, 1.0]`.
- **Offline Capability:** Completely local, zero network calls, zero data leaves the device.

---

## 2. Sefaria Library Provider

- **Endpoint:** `https://www.sefaria.org/api`
- **Authentication:** Public API (no secret key required for standard lookups).
- **Supported Capabilities:**
  - `texts/{ref}`: Retrieves full Hebrew/English text of cited passages.
  - `links/{ref}`: Retrieves traditional commentaries and cross-references.
  - `words/{word}`: Lexicon lookups.

---

## 3. Yochai Knowledge Graph (Remote MCP Server)

- **Provider Kind:** Remote HTTP MCP Server (`ServerKind.remoteHTTP`).
- **Endpoint URL:** `https://api.yochai.org/mcp/v1`
- **Preset Configuration:**
  - Available in Hanlin Settings → Model Context Protocol → Add Server → **Preset: Yochai Knowledge Graph**.
  - Secret Key: Enter your personal API key. The key is securely stored in Keychain / encrypted preferences and is masked in all logs and json exports.
- **Capabilities Exposed to Agent:**
  - `yochai_search`: Searches concepts, books, and rabbinic authors in the knowledge graph.
  - `yochai_lookup`: Resolves canonical node identifiers and structural relations.

---

## 4. Cairo Genizah Research Skill

- **Package:** `Skills/cairo-genizah-research.zip`
- **Installation:**
  1. In Hanlin, navigate to **Skills Catalog** → **Import Skill Archive**.
  2. Select `cairo-genizah-research.zip`.
  3. Hanlin validates the manifest, unpacks the scripts to a sandboxed directory, and registers the tools.
- **Runtime:**
  - Executed via `execute_skill_resource` tool in the embedded Python runtime.
  - Network: Calls `https://genizah.genizah.org/api` via HTTPS.
  - State directory: Managed automatically in sandboxed workspace.

---

## 5. App Group Shared Container (`group.com.davidpovarsky.itorah`)

To enable instant book sharing between Hanlin and Maktabah without duplicate storage:
1. Both apps must be signed with the entitlement:
   ```xml
   <key>com.apple.security.application-groups</key>
   <array>
       <string>group.com.davidpovarsky.itorah</string>
   </array>
   ```
2. Container directory layout:
   ```text
   AppGroup/
     └── seforim.db              (SQLite library catalog)
     └── Otzaria/                (Full text seforim directory)
     │     ├── Tanakh/
     │     ├── Mishnah/
     │     └── Talmud/
     └── manifest.json           (Corpus version and generation hash)
   ```
