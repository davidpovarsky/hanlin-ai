# Torah Photo Study — Physical iPad Runbook (Tier T5)

**Target Device:** Apple iPad (iPadOS 17 or higher) with optical camera  
**Required Binaries:** Signed builds of Hanlin (`AI_HLY`) and Maktabah (`Maktabah-iOS`) sharing `group.com.davidpovarsky.itorah`  

---

## 1. Prerequisites & Sideloading

1. Ensure both apps are built and signed with the matching Apple Developer profile containing:
   - App Group: `group.com.davidpovarsky.itorah`
   - Camera & Photo Library Usage descriptions.
2. Install both apps onto the physical iPad via Xcode (`Devices and Simulators`), Apple Configurator, or authorized MDM/sideloading profile.
3. Launch Maktabah first to initialize the library catalog (`seforim.db`) inside the shared App Group.

---

## 2. Test Step 1: Physical Camera Capture & Crop Selection

1. Open Hanlin on the iPad.
2. Navigate to the Torah Photo Study view (camera button or assistant action).
3. Point the iPad camera at a page of an open physical Hebrew book (e.g., Berakhot 2a or Rambam Hilkhot De'ot).
4. Capture the photo.
5. In the interactive crop overlay, drag the bounding box handles to frame 3–5 lines of text.
6. Verify:
   - The selected region maintains correct Hebrew RTL orientation.
   - The crop handles respond smoothly to touch gestures.

---

## 3. Test Step 2: Offline OCR & Deterministic Identification

1. Put the iPad into **Airplane Mode** (disable Wi-Fi and Cellular).
2. Tap **"זהה מקור" (Identify Source)**.
3. Verify:
   - Apple Vision OCR executes locally without error.
   - The raw transcription card displays the recognized Hebrew lines.
   - `TorahSourceResolver` identifies the passage and presents the canonical locator (e.g. `Berakhot.2a`).
   - The card shows status **"מאומת" (Verified)** with score components (Lexical Coverage, Sequence Order).
   - Zero network requests are made.

---

## 4. Test Step 3: Deep Link Navigation to Maktabah

1. On the verified source result card, tap **"פתח ב-Maktabah" (Open in Maktabah)**.
2. Verify:
   - iOS prompts or immediately opens Maktabah via `maktabah://study?...`.
   - Maktabah opens directly to the exact tractate, page, and highlighted line.
   - Navigating forward and backward in Maktabah functions properly.
3. Switch back to Hanlin and verify that the photo study session state is completely preserved.

---

## 5. Diagnostic Log Export (Sanitized)

To export verification evidence from the iPad:
1. In Hanlin Settings, select **Export Diagnostics**.
2. Verify that no private user images, personal notes, or secret API keys are included in the generated archive.
3. Transfer the exported diagnostics file to your development workstation for audit.
