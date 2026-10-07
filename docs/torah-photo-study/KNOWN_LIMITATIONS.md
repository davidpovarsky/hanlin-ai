# Torah Photo Study — Known Limitations & External Prerequisites

---

## 1. Physical Device & Hardware Prerequisites (Tier T5)
- **Status:** `BLOCKED` in current development environment.
- **Prerequisite:** Testing optical camera performance under real lighting conditions, page curves, and lens glare requires a physical Apple iPad running iPadOS 17 or higher.
- **Runbook:** See [`docs/torah-photo-study/DEVICE_RUNBOOK.md`](file:///C:/Users/DAVID/Code/hanlin-torah-photo-study/docs/torah-photo-study/DEVICE_RUNBOOK.md) for step-by-step instructions.

---

## 2. External Service & API Key Prerequisites (Tier T3)
- **Yochai Knowledge Graph:**
  - Connecting to the remote MCP server requires a valid `YOCHAI_API_KEY`.
  - The client integration and transport abstraction are fully built and tested; live graph queries will activate immediately once the user enters their key in Hanlin Settings.
- **Advanced OCR (HebVL / Qwen-VL):**
  - Requires an active inference endpoint with GPU resources.
  - The standard pipeline defaults to Apple Vision OCR, which is completely offline, highly performant, and requires zero external credentials.

---

## 3. iOS Embedded Runtime Constraints
- **Embedded Python:**
  - The iOS sandboxed environment supports pure-Python libraries.
  - Third-party packages requiring native C/C++ extensions cannot be installed dynamically at runtime via pip; they must be compiled into the binary or wrapped as native Swift frameworks.
  - The Cairo Genizah research scripts (`search.py`, `browse.py`) are strictly written using standard library modules and pure-Python HTTP requests, ensuring complete compatibility with iOS.

---

## 4. Offline vs. Online Capabilities
- **Completely Offline:**
  - Camera capture and region selection.
  - Apple Vision OCR Hebrew text recognition.
  - Normalization, niqqud stripping, and deterministic passage resolution.
  - Reading full text of seforim stored in `group.com.davidpovarsky.itorah`.
  - Deep linking from Hanlin to Maktabah.
- **Requires Internet Connection:**
  - Sefaria online commentary links and cross-references.
  - Yochai semantic concept graph queries.
  - Cairo Genizah fragment searches on `genizah.genizah.org`.
