# Hanlin Platform — Semantic Coverage Audit (PASS 4.1)

**Generated:** 2026-10-13T19:05:37.607Z  
**Authoritative MASTER SHA-256:** `bf76406cee09800635933f6d61c64e3632c243b2ee2c037df5d969d8e3be07f4`  
**Total MASTER Scenarios:** 493  

---

## 1. Executive Disposition Summary

| Disposition Category | Count | Percentage | Description |
|---|---|---|---|
| **REUSED_VERIFIED_PASS** | 377 | 76.5% | Authentically passing previous executions with proven clean dependency closures |
| **NOT_RUN / NEEDS_TEST** | 24 | 4.9% | Semantically corrected or targeted tests pending authorized focused execution |
| **NOT_RUN_DEVICE** | 78 | 15.8% | Physical Apple hardware / Apple Intelligence obligations truthfully open |
| **BLOCKED_EXTERNAL** | 10 | 2.0% | Live 3rd-party provider credentials (OpenAI/Anthropic/Google/GitHub) not committed |
| **BLOCKED_DEPENDENCY** | 2 | 0.4% | Unpinned upstream package (apple/coreai-models) |
| **BLOCKED_INPUT_MODEL_FIXTURE** | 2 | 0.4% | Unsupplied redistributable GGUF / .aimodel local weights |
| **FAILED** | 0 | 0.0% | Active failures |

---

## 2. Key Semantic Repairs Completed

1. **FINAL-01 through FINAL-12 Remapping:**
   - `FINAL-01`: Authentic Phase 1 HanlinPlatform swift-test pass.
   - `FINAL-02`: Node runtime TAP and unit TAP suites.
   - `FINAL-03`: Correctly marked `NOT_RUN` pending fresh iPadOS 27 simulator build-for-testing.
   - `FINAL-04`: Broken down into 260 individual case decisions (235 verified reusable, 25 affected pending focused run).
   - `FINAL-05`: All 7 UI families accounted for, correctly marked `NOT_RUN` (prior synthetic NativeScript evidence invalid).
   - `FINAL-06` & `FINAL-07`: Correctly marked `NOT_RUN` pending explicit operator CI authorization.
   - `FINAL-08`: Truthfully marked `NOT_RUN_DEVICE`.
   - `FINAL-09`: Dedicated semantic test `final09LiveToolDiscoveryAndExecution` added to `MasterScenarioSemanticAcceptanceTests`.
   - `FINAL-10`: Dedicated semantic test `final10ColdRelaunchStateRestorationAndToolReset` added.
   - `FINAL-11`: Dedicated semantic test `final11CancellationAndImmediateNextRunCleanliness` added.
   - `FINAL-12`: Dedicated semantic test `final12InvariantsAndToolsCrossJoinAudit` added.

2. **MiniApp & Host Services Routing Repairs:**
   - `APPENG-03`: Remapped from package catalog test to real bridge E2E test.
   - `APPENG-04`: Remapped from session cleanup test to canonical MiniApp tool execution test.
   - `APPENG-05`: Remapped from unit test to actual `HanlinExpoProductionE2ETests` UI test.
   - `SCRIPTARCH-04` & `SCRIPTARCH-05`: Remapped to real host services execution in `fs01`.

3. **Elimination of Generic iOS 26 Archive Substituting for Build Obligations:**
   - 29 `build_command` obligations audited: audit scenarios converted to exact verifiable repository audits; actual build obligations marked `NOT_RUN` pending iPadOS 27 build.

---

## 3. Dedicated E2E Obligations (E2E-A through E2E-J)

| ID | Title | Implementation Target | Disposition | Status Note |
|---|---|---|---|---|
| **E2E-A** | Skill Import & Package Policy Removal | `AI_HLY/Downstream/AgentSkills/SkillImporter.swift` | **NEEDS_TEST** | Streaming 64KB staging and /var alias support implemented; pending focused Apple run. |
| **E2E-B** | Agent Package Management & Accessible Filesystem (Python/Node/Shell) | `AI_HLY/Downstream/RuntimeCore` | **NEEDS_TEST** | Shared workspace and wheel install verified locally in unit tests; pending focused Apple run. |
| **E2E-C** | Skill-Driven Progressive Discovery (load_skill / tool_search) | `NativeToolCatalog / HanlinAISDKToolAdapter` | **REUSED_VERIFIED_PASS** | Verified by CanonicalToolAuthorityTests and ToolSearchTool tests. |
| **E2E-D** | Personal Data & System Services / Capabilities Simplification | `HanlinHostCapabilityAuthority` | **REUSED_VERIFIED_PASS** | Verified by HanlinUnifiedHostServicesAgentAcceptanceTests. |
| **E2E-E** | Scripting Analyzer & Bundler | `HanlinScriptCompiler` | **REUSED_VERIFIED_PASS** | Verified by HanlinScriptingBundlerTests in HanlinPlatform. |
| **E2E-F** | Limits, Streaming & Cancellation | `APIManager / APIManagerStreamSession` | **REUSED_VERIFIED_PASS** | Verified by APIManagerStreamingTests and MockLocalLLMController. |
| **E2E-G** | Remote AI/Provider Loop Consolidation | `HanlinAISDKAgentEngine` | **REUSED_VERIFIED_PASS** | Consolidated text/tool execution verified. |
| **E2E-H** | Shared cwd across Python, Node, Shell with package tools | `HanlinRuntimeBroker / RuntimeFileLayout` | **NEEDS_TEST** | FS-01 multi-engine shared workspace test implemented; pending focused Apple run. |
| **E2E-I** | npm/MCP Installation & Single MCP Protocol Stack | `NodePackageManager / MCPClientSession` | **REUSED_VERIFIED_PASS** | MCP protocol stack verified in Phase 1 test suite. |
| **E2E-J** | NativeScript & Expo MiniApps | `HanlinNativeScriptRuntime / HanlinExpoRuntime` | **NEEDS_TEST** | Bridge session clearing and challenge nonce proofs implemented; pending focused Apple run. |

---

## 4. Complete 493 MASTER Scenario Disposition Ledger

| ID | Requirement | Layer | Disposition | Scenario | Expected Outcome | Audit Note |
|---|---|---|---|---|---|---|
| **AUD-01** | R01,R26 | U/B | `REUSED_VERIFIED_PASS` | רשום git remote, branch, HEAD ו־status לפני עבודה; השווה לענף המוגדר. | אין שינוי ב־main או ריפו אחר; שינויים קיימים נשמרים; baseline SHA מתועד. |  |
| **AUD-02** | R01 | U | `REUSED_VERIFIED_PASS` | מנה את כל git-tracked production sources, כולל generated runtime resources ו־native bridges. | כל קובץ מסווג reviewed/not-applicable; אין הסתמכות על 300 קבצי compare או default-branch search. |  |
| **AUD-03** | R01,R22 | U/I | `REUSED_VERIFIED_PASS` | לכל candidate gate עקוב מה־call site עד backend; נסה אותו בפרופיל production. | ה־inventory מבדיל gate פעיל, declaration בלבד, test-only ו־correctness guard. |  |
| **AUD-04** | R01,R25 | U/B | `REUSED_VERIFIED_PASS` | השווה restriction-inventory לפני/אחרי; חפש את אותם תנאים גם בקוד ארוז. | אין gate שהועבר לשם/קובץ אחר; לכל retained restriction יש סיבה ובדיקה. |  |
| **AUD-05** | R01,R23 | I | `REUSED_VERIFIED_PASS` | בנה קטלוג עם כל משפחות הכלים מופעלות בפרופיל בדיקה; השווה schemas, aliases ו־executors. | אין tool שאין לו executor, Skill/דרך גילוי או test mapping; meta tools נספרים בנפרד. |  |
| **AUD-06** | R01,R17 | I | `REUSED_VERIFIED_PASS` | בנה קטלוג עם חלק מהכלים כבויים לפי UserDefaults fixture. | המשתמש נשאר בעל שליטה; audit מציג disabled, והבדיקה לא משנה preference. |  |
| **AUD-07** | R22,R25,R43 | B | `REUSED_VERIFIED_PASS` | השווה baseline מול final diff ובמיוחד קבצי מקור היסטוריים ששונו/נמחקו ובדיקות שנמחקו/עודכנו. | Direct edits to former upstream files are allowed; every large deletion/migration is explained by the new authoritative path and parity evidence; no suite is deleted merely to hide a failure. |  |
| **AUD-08** | R26 | U/B | `REUSED_VERIFIED_PASS` | בדוק שלכל R ולכל מזהה test במסמך יש תוצאה ונתיב evidence. | חוסר mapping, NOT_RUN או BLOCKED מוצגים במפורש; לא נספרים כ־PASS. |  |
| **ZIP-01** | R02 | I/S/D | `NOT_RUN` | ייבא F02 root ZIP עם SKILL.md, hanlin.json ו־agents/openai.yaml. | preview/install/refresh/relaunch מצליחים; אותם metadata וגוף זמינים. | Semantic test implementation updated on current HEAD; pending authorized run. |
| **ZIP-02** | R02 | I/S/D | `NOT_RUN` | ייבא אותם bytes תחת fixture-runtime/ wrapper. | אותה תוצאה כמו ZIP-01; wrapper לבדו אינו שגיאה. | Semantic test implementation updated on current HEAD; pending authorized run. |
| **ZIP-03** | R02 | I/S | `REUSED_VERIFIED_PASS` | בדוק תיקיות staging שנוצרו עם ובלי directory hint ועם slash מסיים. | SKILL.md מתקבל בשני המקרים; diagnostic מזהה את תנאי הכשל אם קיים. |  |
| **ZIP-04** | R02,R09 | S/D | `NOT_RUN_DEVICE` | שחזר Foundation URL aliases של /var ו־/private/var באותו temp directory. | אין false escape על אותו יעד; אין הנחה שבדיקת Linux מספיקה. |  |
| **ZIP-05** | R02 | I/S/D | `NOT_RUN_DEVICE` | ייבא מתוך תיקייה בשם עברית space % #? וב־entry עם שם כזה. | אין double encoding, no missing file, bytes ושמות נשמרים. |  |
| **ZIP-06** | R02 | U/I | `REUSED_VERIFIED_PASS` | ZIP עם entries מפורשים לתיקיות ו־ZIP בלי directory entries. | שניהם מיובאים; parent directories נוצרים כנדרש. |  |
| **ZIP-07** | R02,R04 | I | `REUSED_VERIFIED_PASS` | SKILL יחד עם LICENSE, assets/data.bin, sample.xlsx, source.swift ו־module.wasm. | אין unsupportedFileType של Hanlin; כל bytes נגישים לאחר install. |  |
| **ZIP-08** | R02,R18 | I/S | `NOT_RUN` | ייבא archive מעל 25MiB ונתון expanded מעל 64MiB עם marker בסוף. | אין cutoff ישן; bytes מלאים, cancellation זמין ו־memory אינו צומח לפי כל archive. | Semantic test implementation updated on current HEAD; pending authorized run. |
| **ZIP-09** | R02 | I | `REUSED_VERIFIED_PASS` | ייבא 1,025 קבצים קטנים, 257 תיקיות ו־resource בעומק 17. | אין limits הישנים; הכל נשמר או כשל OS קונקרטי מתועד. |  |
| **ZIP-10** | R02 | I | `REUSED_VERIFIED_PASS` | resource חוזר בעל compression ratio מעל 100 עם CRC תקין. | אין דחיית ratio; גודל/תוכן לאחר חילוץ נכונים. |  |
| **ZIP-11** | R02 | I/S | `REUSED_VERIFIED_PASS` | נתיב פנימי ./references/a.md ו־references/x/../a.md לאחר normalization חד־משמעי. | ה־resource נפתר נכון בתוך החבילה; אין blanket rejection של substring. |  |
| **ZIP-12** | R02 | I/S | `REUSED_VERIFIED_PASS` | symlink פנימי תקין אל resource, על filesystem שתומך בו. | אין דחיית package שלם; משאב נקרא לפי semantics מתועדים של ספריית ZIP. |  |
| **ZIP-13** | R02,R22 | I | `REUSED_VERIFIED_PASS` | ZIP קטוע או CRC שגוי במקום F02. | import נכשל כ־archive/data error; Skill קודם לא נפגע; אין installation חלקי. |  |
| **ZIP-14** | R02,R22 | I | `REUSED_VERIFIED_PASS` | ZIP תקין ללא SKILL.md או עם SKILL.md שאינו UTF-8. | שגיאת פורמט מדויקת; אין טענת escape/permission ואין רישום ריק. |  |
| **ZIP-15** | R02 | I/S | `REUSED_VERIFIED_PASS` | outer pack מכיל שתי תיקיות Skill עצמאיות. | preview מציג 2; install רושם את שתיהן; אין בחירת SKILL ראשון בלבד. |  |
| **ZIP-16** | R02,R06 | I/S/D | `NOT_RUN_DEVICE` | ייבא Hanlin-Skills-Pack-FIXED.zip שסופק, עם 10 קובצי skill.zip פנימיים. | 10 תוצאות פריט ו־10 Skills זמינים; אם המקור חסר ציין BLOCKED_INPUT ולא PASS. |  |
| **ZIP-17** | R02,R06 | I/S/D | `NOT_RUN_DEVICE` | ייבא Hanlin-Skills-Pack.zip המקורי באותו מסלול bulk. | wrapper פנימי מתקבל; metadata מלא לכל 10; אין דרישה ל־ZIP שלישי. |  |
| **ZIP-18** | R02,R04 | I/S | `REUSED_VERIFIED_PASS` | bulk pack שבו שני Skills שונים מצהירים על אותו ID. | מוצג conflict שמאפשר resolution מפורש; אין דריסה/בחירה שקטה. |  |
| **ZIP-19** | R02,R22 | I | `REUSED_VERIFIED_PASS` | כשל write מוזרק באמצע install ועדכון Skill קיים; לאחר מכן הפעל relaunch. | הגרסה הישנה תקינה; אין orphan catalog entry; staging מנוקה. |  |
| **ZIP-20** | R02,R22 | I/S | `REUSED_VERIFIED_PASS` | בטל download/extraction של package גדול אחרי קבלת כמה chunks. | אין installed success; task מפסיק; גרסה קודמת נשמרת. |  |
| **ZIP-21** | R02,R22 | I | `REUSED_VERIFIED_PASS` | ZIP עם entry המפנה מחוץ ליעד החילוץ; sentinel זמני מחוץ ל־root. | אין כתיבה שקטה מחוץ ליעד import; שגיאת פורמט/יעד או mapping מפורש; runtime filesystem אינו מושפע. |  |
| **ZIP-22** | R02,R22 | I/S | `REUSED_VERIFIED_PASS` | ZIP עם paths שמתנגשים אחרי Unicode normalization/case folding ב־filesystem המטרה. | conflict מדויק או טיפול מפורש ללא השחתת bytes; אין סריקת אבטחה נוספת כללית. |  |
| **META-01** | R03 | U/I | `REUSED_VERIFIED_PASS` | פענח hanlin.json המקורי עם installedAt/updatedAt כמחרוזות ISO-8601. | אין typeMismatch; preferredToolIDs/triggerHints/keywords זהים לקלט. |  |
| **META-02** | R03 | U/I | `REUSED_VERIFIED_PASS` | אותו metadata עם תאריך 2026-10-04T12:00:00.123Z. | fractional date נקרא; אין fallback שמרוקן metadata. |  |
| **META-03** | R03 | U/I | `REUSED_VERIFIED_PASS` | טען store ישן עם מספרי Date של Foundation. | תאריך מפוענח ביחס epoch הנכון; migration אינו משנה סדר או hints. |  |
| **META-04** | R03 | U/I | `REUSED_VERIFIED_PASS` | metadata עם arrays תקינים וללא שדות תאריך. | ברירות מחדל מתועדות; arrays נשמרים; אין reject. |  |
| **META-05** | R03 | U/I | `REUSED_VERIFIED_PASS` | metadata עם שדה unknown ו־baseSkillID; בצע import -> export -> import. | המידע הידוע אינו נאבד; unknown data נשמר לפי codec מתועד. |  |
| **META-06** | R03 | U/I/S | `REUSED_VERIFIED_PASS` | hanlin.json פגום, אך SKILL.md תקין. | error/preview correction גלוי; אין overwrite שקט לקובץ metadata ריק. |  |
| **META-07** | R03 | U/I | `REUSED_VERIFIED_PASS` | description מצוטט עם ':' ומרכאות escaped. | הטקסט המלא נשמר ומופיע באינדקס. |  |
| **META-08** | R03 | U/I | `REUSED_VERIFIED_PASS` | frontmatter עם description: > ועם description: \\| בשני fixtures. | multiline נקרא נכון; ערך אינו התו > או \\| בלבד. |  |
| **META-09** | R03 | U/I | `REUSED_VERIFIED_PASS` | קובץ עם BOM, CRLF, עברית ו־--- בתוך גוף Markdown. | frontmatter מופרד רק בגבול שלו; גוף לא נחתך. |  |
| **META-10** | R03 | U/I | `REUSED_VERIFIED_PASS` | export של Skill עם display title 'Code Execution' ו־ID מכני קיים. | ה־name/ID המיוצא נשאר importable; display title אינו משחית מזהה. |  |
| **META-11** | R03,R04 | I/S | `REUSED_VERIFIED_PASS` | install, refresh קטלוג, terminate/relaunch ואז load_skill. | אותו גוף, IDs, triggers ו־preferred tools בכל השלבים. |  |
| **META-12** | R03,R04 | I/S | `REUSED_VERIFIED_PASS` | המשתמש כיבה Skill ואז עדכן/ייבא אותו מחדש. | בחירת disable אינה נעלמת בלי פעולה מפורשת. |  |
| **META-13** | R03 | I/S | `REUSED_VERIFIED_PASS` | ייבא .md בלי hanlin.json. | import מצליח; אין invented hints; workflow דרך הוראות/tool_search עדיין בר־ביצוע. |  |
| **META-14** | R04 | I/S | `REUSED_VERIFIED_PASS` | ייבא override מפורש ל־code, ו־custom Skill אחר בשם שונה. | override פעיל במקום הנכון; custom לא נעלם ולא מוחק unrelated skill. |  |
| **META-15** | R04 | I/S | `REUSED_VERIFIED_PASS` | קרא references/release..notes.md, UTF-8 resource ו־binary asset. | .. בתוך שם חוקי אינו נדחה; binary חוזר descriptor נגיש ולא missing. |  |
| **META-16** | R03,R22 | I | `REUSED_VERIFIED_PASS` | הזרק כשל בשמירת metadata/state במהלך update. | ה־store והקבצים חוזרים למצב עקבי; אין Skill רשום עם body/metadata מגרסאות שונות. |  |
| **DISC-01** | R05 | I/S | `REUSED_VERIFIED_PASS` | בצע round 0 בפרופיל עם כלים קיימים אך ללא Skill טעון. | meta tools ואינדקס metadata קיימים; schemas של כל העולם אינם נשלחים. |  |
| **DISC-02** | R05 | I/S | `REUSED_VERIFIED_PASS` | load_skill ל־Code כאשר סכום preferred schemas גדול מ־4,096 bytes. | כל preferred tool קיים וזמין נחשף; אין חיתוך בגלל 4KB. |  |
| **DISC-03** | R05 | I | `REUSED_VERIFIED_PASS` | טען Skill אחד עם schema גדול יותר מ־4KB לבדו. | הכלי ניתן לקריאה; אין starvation של schema יחיד. |  |
| **DISC-04** | R05 | I | `REUSED_VERIFIED_PASS` | טען שני Skills באותה ריצה עם alias משותף. | הוראות שני ה־Skills זמינות; alias לא מוכפל. |  |
| **DISC-05** | R05 | I/S | `REUSED_VERIFIED_PASS` | אחרי load_skill בצע tool call בסבב הבא ונתח request בפועל. | ה־schema וה־instructions מגיעים לספק לפני קריאת הכלי. |  |
| **DISC-06** | R04,R05 | I/S | `REUSED_VERIFIED_PASS` | סיים run והתחל run חדש אחרי שינוי catalog revision. | אין schema ישן של כלי שנמחק; metadata העדכני קיים. |  |
| **DISC-07** | R05 | U/I | `REUSED_VERIFIED_PASS` | tool_search עבור exact alias אחרי טעינת Skill לא־רלוונטי. | exact alias קודם; skill boost לא מסתיר אותו. |  |
| **DISC-08** | R05 | U/I | `REUSED_VERIFIED_PASS` | tool_search עם query שאין לו שום התאמה לאחר טעינת Code. | אין תוצאות רק בגלל boost; חזרה מפורשת של no matches. |  |
| **DISC-09** | R05 | U/I | `REUSED_VERIFIED_PASS` | חיפוש בעברית 'הרצת פייתון' ובאנגלית 'python execution'. | מתגלה הכלי המקומי המתאים דרך metadata; אין router קשיח של prompt. |  |
| **DISC-10** | R05,R07 | I | `REUSED_VERIFIED_PASS` | fixture catalog עם 27 כלים מתאימים; עבור בכל דפי החיפוש. | כל 27 זמינים בגילוי; אין cutoff של 10, ואין כפילויות. |  |
| **DISC-11** | R05 | I | `REUSED_VERIFIED_PASS` | load_skill עבור ID לא־קיים ו־tool_search עם arguments לא־תקינים. | isError/outcome מתאימים; אין succeeded עבור טקסט Error. |  |
| **DISC-12** | R05,R24 | I/S | `REUSED_VERIFIED_PASS` | מודל מחזיר תשובה 'אין כלים' בלי קריאת discovery בתסריט F06. | ה־test מזהה התנהגות שגויה; לא משכתב את תשובת המודל ומציג כאילו בוצע כלי. |  |
| **DISC-13** | R05 | U/B | `REUSED_VERIFIED_PASS` | סקור diff ובצע assertion שאין intent routing hardcoded למילים Python/npm/shell. | בחירת Skill נשארת של המודל; metadata/catalog הם מנגנון הבחירה. |  |
| **DISC-14** | R04,R05 | I | `REUSED_VERIFIED_PASS` | load_skill חוזר פעמיים לאותו ID באותה ריצה. | פעולה idempotent; instructions לא מוכפלים; רשימת exposed tools נכונה. |  |
| **DISC-15** | R05,R17 | I | `REUSED_VERIFIED_PASS` | preferredToolID מפנה לכלי שהמשתמש כיבה. | הוא מסומן unavailable/disabled; load_skill אינו מפעיל אותו מאחורי הגב. |  |
| **DISC-16** | R05,R23 | I | `REUSED_VERIFIED_PASS` | preferred logical ID/alias נדרש לעבור canonical resolution. | מוצג alias נכון; אין פרסום שם שאינו callable. |  |
| **DISC-17** | R05,R24 | I/S | `REUSED_VERIFIED_PASS` | provider מפצל שם/arguments של tool על streaming chunks. | נוצרת קריאה אחת עם arguments מלאים; אין execution חלקי/כפול. |  |
| **DISC-18** | R05,R23 | I | `REUSED_VERIFIED_PASS` | provider מחזיר alias לא־ידוע או invalid JSON. | כשל מובנה הניתן להמשך; אין קריסת loop/dispatch לכלי אחר. |  |
| **DISC-19** | R05,R18 | I/S | `REUSED_VERIFIED_PASS` | F06 מבצע 33 סבבים קצרים תחת maxSteps=40. | הסבב ה־33 מגיע; אין עצירה קשיחה ב־32. |  |
| **DISC-20** | R05,R18 | I/S | `REUSED_VERIFIED_PASS` | אותו F06 תחת maxSteps=3 ואז cancellation ידני בהרצה בלי תקרה. | עצירה לפי ההגדרה/ביטול בלבד; reason מפורש ומצב UI עקבי. |  |
| **DISC-21** | R05 | U/I | `REUSED_VERIFIED_PASS` | בנה פעמיים אותו exposed alias set ו־provider request. | ordering יציב ודטרמיניסטי; אין churn בגלל איטרציה על Set. |  |
| **DISC-22** | R05 | I/P | `REUSED_VERIFIED_PASS` | בקשת 'שלום' או כתיבה יצירתית שאינה דורשת כלי. | אין טעינה כפויה של Code/כל הכלים; הנחיית discovery לא הופכת לכלי חובה בכל תשובה. |  |
| **TOOLS-01** | R07 | I/S | `REUSED_VERIFIED_PASS` | list_tools/המקבילה האמיתית עם native, legacy, MCP ו־Script fixtures. | כל logical IDs מופיעים פעם אחת עם provider ומצב נכון. |  |
| **TOOLS-02** | R07 | I | `REUSED_VERIFIED_PASS` | catalog כולל 150 כלים ו־pagination בגודל 17. | איסוף כל הדפים שווה לקטלוג בדיוק; אין ניחוש של מספר כלים. |  |
| **TOOLS-03** | R07 | I/S | `REUSED_VERIFIED_PASS` | get_runtime_capabilities לפני startup ואחרי הפעלת Python/Node. | גרסה ומצב נלקחים מה־backend; אין hardcoded ready. |  |
| **TOOLS-04** | R07,R24 | I | `REUSED_VERIFIED_PASS` | health check נכשל ואז retry אמיתי מצליח. | מצב unavailable מתעדכן ל־ready רק אחרי הצלחה; אין stale false/true. |  |
| **PKGT-01** | R08 | I/S | `REUSED_VERIFIED_PASS` | גלה את package manager דרך Skill ו־tool_search ואז action=list לשני runtimes. | schema פורסם; הרשימות משקפות את managers האמיתיים ולא subprocess חיצוני. |  |
| **PKGT-02** | R08 | I/S | `REUSED_VERIFIED_PASS` | preview ל־F04 CJS ול־Python wheel. | פרטי spec/version/source/dependencies חוזרים בלי התקנה כפויה. |  |
| **PKGT-03** | R08 | I/S/D | `NOT_RUN_DEVICE` | install ל־F04 CJS ואחריו execute_javascript_code עם runtime=node. | קריאה עם 21 מחזירה 42; הותקן באותו runtime שבו הסוכן עובד. |  |
| **PKGT-04** | R08 | I/S/D | `NOT_RUN_DEVICE` | install ל־F04 Python wheel ואז import בשתי ריצות חדשות. | answer=42 בשתיהן; לא הצלחה רק בתוך probe זמני. |  |
| **PKGT-05** | R08 | I/S | `REUSED_VERIFIED_PASS` | probe של package subpath-only ו־CLI-only. | installed status נשמר; root-import failure אינו כשל התקנה מדומה. |  |
| **PKGT-06** | R08 | I/S | `REUSED_VERIFIED_PASS` | uninstall package של fixture ואז list ו־import חדש. | הרשומה והגישה הוסרו; packages אחרים נשמרים. |  |
| **PKGT-07** | R08,R24 | I | `REUSED_VERIFIED_PASS` | action/runtime לא־תקינים או spec חסר ב־install. | schema validation מדויקת; אין צד־אפקט. |  |
| **PKGT-08** | R08,R18 | I/S | `REUSED_VERIFIED_PASS` | install איטי, status/progress ואחריו cancel. | אין timeout שרירותי ישן; ביטול משחרר task/transaction ומסומן cancelled. |  |
| **PKGT-09** | R08,R22 | I | `REUSED_VERIFIED_PASS` | הזרק commit failure אחרי extraction והפעל list/relaunch. | אין installed success; rollback נכון; state וקבצים תואמים. |  |
| **PKGT-10** | R08,R23 | I/S | `REUSED_VERIFIED_PASS` | אותה קריאת install מתקבלת פעמיים עם אותו call ID עקב retry streaming. | אין side effect כפול; תוצאה עקבית עם transaction המקורי. |  |
| **PKGT-11** | R08 | I/S | `REUSED_VERIFIED_PASS` | שני package installs שונים במקביל. | אין החלפת cwd/dependencies/transaction IDs; כל תוצאה שייכת לחבילה הנכונה. |  |
| **PKGT-12** | R08,R24 | I | `REUSED_VERIFIED_PASS` | שגיאת registry 404/500 או no network. | כשל מפורש עם stage/source; לא sandbox denial, לא install success. |  |
| **FS-01** | R09 | I/S/D | `NOT_RUN` | Python כותב F01 sample.txt, Node קורא ומוסיף שורה, shell קורא את התוצאה באותו context. | שלוש השכבות רואות אותו cwd ותוכן; אין workspace מנותק לכל tool. | Semantic test implementation updated on current HEAD; pending authorized run. |
| **FS-02** | R09 | I/S | `REUSED_VERIFIED_PASS` | קרא path מוחלט לתיקייה נגישה בתוך app container, מחוץ ל־clients. | אין Hanlin pathEscapesRoot; התוכן נכון. |  |
| **FS-03** | R09 | I/S | `REUSED_VERIFIED_PASS` | מתוך workspace-a גש ל־../shared/data.json שהבדיקה יצרה. | היעד הנגיש נקרא; .. אינו blacklist של runtime. |  |
| **FS-04** | R09 | I/S/D | `NOT_RUN_DEVICE` | קרא וכתוב דרך symlink פנימי ו־symlink ל־sibling test directory נגיש. | לינק תקין אינו נחסם; אותה תוצאת filesystem שהפעולה אמורה לתת. |  |
| **FS-05** | R09 | I/S | `REUSED_VERIFIED_PASS` | קרא/כתוב את עברית space % #?.txt דרך file URL ודרך string path. | אין double encoding; bytes זהים בכל מסלול. |  |
| **FS-06** | R09 | S/D | `NOT_RUN_DEVICE` | בחר תיקייה ב־Files, הענק security scope, כתוב fixture והפעל relaunch. | bookmark מתחדש כנדרש; גישה חיצונית נבחרת עובדת ללא hardcoded root. |  |
| **FS-07** | R09 | S/D | `NOT_RUN_DEVICE` | בטל/יישן את bookmark והרץ אותה קריאה. | שגיאת OS/scope ספציפית; אין fabricated success או בקשת אישור Hanlin חדשה. |  |
| **FS-08** | R09,R22 | I/S | `REUSED_VERIFIED_PASS` | צור שני agent contexts במקביל, עם cwd ו־קובץ marker שונים. | אין החלפת cwd/נתונים בין contexts; shared access רק כשהנתיב מבוקש. |  |
| **FS-09** | R09 | I/S | `REUSED_VERIFIED_PASS` | רשום MCP package root חיצוני שנבחר, הפעל entrypoint ואז הסר את הרישום. | השרת רץ; uninstall אינו מוחק קבצים שאינם בבעלות ההתקנה. |  |
| **FS-10** | R09,R22 | I/S | `REUSED_VERIFIED_PASS` | בצע migration של MCP descriptor ישן בעל path container קודם. | resolved path מצביע לחבילה הקיימת; אין דרישה להורדה חוזרת ללא צורך. |  |
| **FS-11** | R09,R22 | I | `REUSED_VERIFIED_PASS` | נתיב לא־קיים/קובץ במקום directory/יעד read-only. | כשל filesystem מדויק; לא permission policy כללי ולא קריסה. |  |
| **FS-12** | R09,R22 | I | `REUSED_VERIFIED_PASS` | directory עם sentinel; בצע uninstall/update/rollback של package סמוך. | רק קבצים בבעלות transaction משתנים; אין מחיקה גורפת. |  |
| **ENV-01** | R10 | I/S | `REUSED_VERIFIED_PASS` | override ל־HOME ול־PATH באותה קריאת runtime. | ערכים אפקטיביים לפי ההגדרה; אין reservedEnvironmentName. |  |
| **ENV-02** | R10 | I/S | `REUSED_VERIFIED_PASS` | Python module בתיקייה נוספת באמצעות הגדרת PYTHONPATH/search path. | import של המודול מצליח ו־stdlib עדיין זמין. |  |
| **ENV-03** | R10 | I/S | `REUSED_VERIFIED_PASS` | הגדר NODE_PATH עבור CJS resolution ותיקיית package fixture. | CJS פותר לפי המסלול הנתמך; לא נטענת טענה ש־NODE_PATH לבדו פותר ESM. |  |
| **ENV-04** | R10 | I/S | `REUSED_VERIFIED_PASS` | הגדר npm cache/prefix שונים ל־package operation. | manager משתמש בנתיבים המתועדים; אין reset שקט ל־default. |  |
| **ENV-05** | R10,R22 | I/S | `REUSED_VERIFIED_PASS` | הרץ Python ו־ios_system במקביל עם cwd/env שונים והזרק exception. | ערכי process-global משוחזרים; אין leak אחרי success או exception. |  |
| **ENV-06** | R10 | I/S | `REUSED_VERIFIED_PASS` | שנה setting שמוגדר initialization-only לאחר ש־CPython כבר רץ. | המערכת מבצעת reconfiguration נתמכת או מסבירה restart; אינה משקרת שהערך הוחל. |  |
| **ENV-07** | R10,R24 | I | `REUSED_VERIFIED_PASS` | הכנס env בשם FIXTURE_API_KEY עם ערך סינתטי; הפעל diagnostics. | ה־runtime מקבל את הערך כשהתבקש, אך logs/results ציבוריים לא מדפיסים אותו. |  |
| **ENV-08** | R10,R22 | I | `REUSED_VERIFIED_PASS` | env name לא־ניתן לייצוג כגון מפתח ריק/עם NUL. | שגיאת פורמט טכנית; אין ניסיון setenv לא־תקין או crash. |  |
| **SH-01** | R11 | I/S/D | `NOT_RUN` | השווה commandsAsArray/ios_executable, dictionary entries ו־tool catalog. | קטלוג הפקודות משקף backend בפועל; אין exact-23 assertion. | Semantic test implementation updated on current HEAD; pending authorized run. |
| **SH-02** | R11 | I/S | `REUSED_VERIFIED_PASS` | רשום command בדיקתי נוסף בשם hanlin_fixture_echo במנגנון הקיים. | ה־runner וה־tool יכולים להפעילו; extraCommandsDictionary אינו חייב להיות ריק. |  |
| **SH-03** | R11 | I/S | `REUSED_VERIFIED_PASS` | הסר framework/סמל של command אחד ב־fixture package. | הפקודה מסומנת unavailable עם dependency מדויק; פקודות קיימות ממשיכות לעבוד. |  |
| **SH-04** | R11 | I/S/D | `NOT_RUN_DEVICE` | program=cat, arguments=[path של F01 sample.txt]. | stdout בדיוק alpha\nbeta\nalpha\n; exit 0. |  |
| **SH-05** | R11 | I/S | `REUSED_VERIFIED_PASS` | program=grep, arguments=['alpha','sample.txt']. | שתי שורות alpha; parser אינו מסווג alpha כנתיב שחייב להתקיים. |  |
| **SH-06** | R11 | I/S | `REUSED_VERIFIED_PASS` | program=sed, arguments=['s/alpha/A/','sample.txt']. | stdout A\nbeta\nA\n; ביטוי sed אינו נחסם בגלל slash. |  |
| **SH-07** | R11 | I/S | `REUSED_VERIFIED_PASS` | program=awk, arguments=['{print $1}','sample.txt']. | אותן שלוש מילים; braces/$ בביטוי אינם policy violation. |  |
| **SH-08** | R11 | I/S | `REUSED_VERIFIED_PASS` | raw command: cat sample.txt \\| grep alpha. | פלט שתי שורות כאשר ios_system המוטמע תומך ב־pipeline; אחרת failure טכני מתועד, לא blacklist של Hanlin. |  |
| **SH-09** | R11 | I/S | `REUSED_VERIFIED_PASS` | raw command: cat sample.txt > copied.txt; קרא copied.txt. | redirection נתמך מגיע ל־backend; copied.txt שווה למקור; לא literal filename '>'. |  |
| **SH-10** | R11 | I/S | `REUSED_VERIFIED_PASS` | raw command: cat < sample.txt; ובהרצה נוספת append >>. | stdin/redirection/append תואמים ל־backend המוצהר; אין פרשנות שגויה ב־argv mode. |  |
| **SH-11** | R11 | I/S | `REUSED_VERIFIED_PASS` | raw command עם ;, && ו־\\|\\| ב־fixtures הצלחה/כשל. | צור capability matrix לפי syntax backend; כל syntax נתמך עובד, unsupported אינו מוסתר. |  |
| **SH-12** | R11 | I/S | `REUSED_VERIFIED_PASS` | raw command עם $VAR, ${VAR}, $(...) ו־backticks תחת fixture חסר side effects. | כל צורה מסווגת לפי תמיכה אמיתית; אין חסימה בשל טקסט בלבד ואין טענת bash מלא. |  |
| **SH-13** | R11 | I/S | `REUSED_VERIFIED_PASS` | argv מובנה לפקודת echo fixture: ['a\\|b','x>y','a;b','$(text)']. | כל argument חוזר מילולית; לא נוצר קובץ ולא מופעלת פקודה נוספת. |  |
| **SH-14** | R11 | I/S | `REUSED_VERIFIED_PASS` | argv עם מחרוזת ריקה, רווחים, apostrophe, double quote ועברית. | נשמרת ההפרדה וה־bytes; empty argument לא נעלם. |  |
| **SH-15** | R11 | I/S | `REUSED_VERIFIED_PASS` | קרא path מוחלט חוקי ו־../shared path. | אין חסימה של Hanlin; ios_system מקבל יעד נכון ולא MiniRoot מצומצם שקט. |  |
| **SH-16** | R11,R16 | I/S/D | `NOT_RUN_DEVICE` | curl אל ${FIXTURE_BASE}/ok.json ב־HTTP, ללא allow_network=true. | תוצאת HANLIN_OK מתקבלת במסלול הנתמך; אין permission prompt פנימי. |  |
| **SH-17** | R11 | I/S | `REUSED_VERIFIED_PASS` | program=wc, stdin=bytes של sample.txt, ללא קובץ. | count תואם ל־3 שורות; stdin מגיע ל־command. |  |
| **SH-18** | R11 | I/S | `REUSED_VERIFIED_PASS` | program=sort על numbers.txt ואז uniq על sample fixture מסודר. | פלט מספרים 1,2,3; פקודות אינן רק listed אלא באמת invoked. |  |
| **SH-19** | R11 | I/S | `REUSED_VERIFIED_PASS` | cp -> stat -> mv -> readlink/ln -> rm על קבצי fixture. | כל הפעולות משקפות מצב קבצים אמיתי; cleanup לא מוחק תיקיית משתמש. |  |
| **SH-20** | R11 | I/S | `REUSED_VERIFIED_PASS` | tar create/extract של תיקיית fixture עם טקסט/Unicode. | roundtrip bytes מלא; scripts לא נסרקים כמקור מסוכן. |  |
| **SH-21** | R11,R22 | I/S | `REUSED_VERIFIED_PASS` | command שאינו קיים ו־command ידוע עם arguments לא־תקינים. | exit/error תואמים; אין success ללא output ואין app crash. |  |
| **SH-22** | R11,R22 | I/S/D | `NOT_RUN_DEVICE` | 50 קריאות קצרות בשני contexts עם stderr/stdout שונים. | streams/cwd משויכים נכון; אין data race או output של קריאה אחרת. |  |
| **JS-01** | R12 | I/S/D | `NOT_RUN_DEVICE` | execute_javascript_code עם runtime=jscore ו־console.log(21*2). | פלט 42; מזהה runtime הוא JSC. |  |
| **JS-02** | R12 | I/S/D | `NOT_RUN_DEVICE` | runtime=node: console.log(process.version); await Promise.resolve(); console.log(42). | Node אמיתי, version אמיתי, פלט 42. |  |
| **JS-03** | R12 | I/S | `REUSED_VERIFIED_PASS` | runtime=auto וקוד setTimeout/Promise ללא import. | נבחר מסלול שתומך ב־async לפי המדיניות המתועדת; אין fake JSC support. |  |
| **JS-04** | R12 | I/S | `REUSED_VERIFIED_PASS` | console.log('sudo docker child_process cluster curl x \\| sh') ו־comments זהים. | הקוד רץ; אין source-word rejection. |  |
| **JS-05** | R12,R13 | I/S/D | `NOT_RUN_DEVICE` | import של node:child_process ו־node:cluster ללא קריאת spawn. | import של builtin שקיים מצליח; אין policy block בגלל שם. |  |
| **JS-06** | R12 | I/S | `REUSED_VERIFIED_PASS` | ESM: import fs from 'node:fs'; כתוב marker וקרא אותו. | ESM נתמך; Skill אינו מייצר require לא־מוגדר. |  |
| **JS-07** | R12,R14 | I/S | `REUSED_VERIFIED_PASS` | CJS package F04 מיובא דרך createRequire ובנפרד ESM package דרך import. | 21*2=42 ו־41+1=42; semantics תואמים, לא wrapper מדומה. |  |
| **JS-08** | R12 | I/S | `REUSED_VERIFIED_PASS` | TypeScript source: const x:number=42; console.log(x); compile_only=false. | קומפילציה וריצה אמיתיות, פלט 42. |  |
| **JS-09** | R12 | I/S | `REUSED_VERIFIED_PASS` | אותו TypeScript עם compile_only=true וקוד שהיה כותב קובץ. | מוחזרים diagnostics/emitted JS; קובץ side-effect לא נוצר. |  |
| **JS-10** | R12,R24 | I/S | `REUSED_VERIFIED_PASS` | TypeScript עם syntax error; JavaScript עם throw new Error('FIXTURE_FAIL'). | compiler/runtime errors נשמרים בנפרד; outcome failed. |  |
| **JS-11** | R12 | I/S | `REUSED_VERIFIED_PASS` | JSC explicit עם API שאין בו, כגון Node fs. | אי־תמיכה מדויקת; אין מעבר מרוחק או דיווח Node/JSC כוזב. |  |
| **MCP-01** | R13 | I/S/D | `NOT_RUN_DEVICE` | הפעל MCP fixture עם initialize -> tools/list -> tools/call שמחזיר 42. | handshake וקריאה מצליחים בשרת האמיתי; stop/restart משאירים host חי. |  |
| **MCP-02** | R13 | I/S | `REUSED_VERIFIED_PASS` | MCP fixture עם child_process import דרך dependency שלא מפעיל process. | אין import-chain veto; tools/list מצליח. |  |
| **MCP-03** | R13 | I/S/D | `NOT_RUN_DEVICE` | בצע action של process שאינו נתמך דרך adapter הבדיקה, ללא syscall מסוכן בתהליך המשתמש. | platformUnsupported נקודתי או in-process implementation מוכח; host אינו נעצר. |  |
| **MCP-04** | R13 | I/B | `REUSED_VERIFIED_PASS` | ב־host פלטפורמה שתומכת ב־subprocess, הרץ fixture subprocess ציבורי קטן. | אין iOS policy גורפת על target אחר; stdout/exit אמיתיים. |  |
| **MCP-05** | R13 | I/S | `REUSED_VERIFIED_PASS` | package כולל .node file שאינו נטען, וכן .wasm כנתונים. | אין rejection של package רק בגלל assets; MCP fixture הרגיל ממשיך לרוץ. |  |
| **MCP-06** | R13,R24 | I/S | `REUSED_VERIFIED_PASS` | fixture מבקש native module באמת אך loader אינו תומך בו. | module/ABI/platform error מפורש; לא anti-bypass denial ולא success. |  |
| **MCP-07** | R13 | I/S | `REUSED_VERIFIED_PASS` | host ללא module hooks שהיו רק עבור policy; בדוק גם TypeScript resolver. | JS רגיל אינו נחסם ללא סיבה; צורך טכני ב־hook עבור feature מסוים מדווח בנפרד. |  |
| **MCP-08** | R13,R22 | I/S/D | `NOT_RUN_DEVICE` | startup error, rapid stop/start, cancel בזמן handshake, ואז שרת תקין. | אין orphan worker, deadlock או host לא־נגיש; השרת התקין מצליח אחריהם. |  |
| **CMD-01** | R11,R23 | I/S/D | `NOT_RUN` | על F01 חדש ומבודד לכל שורה: program=awk, arguments=['{print $1}','sample.txt']. | alpha\nbeta\nalpha\n; exit code 0. | Semantic test implementation updated on current HEAD; pending authorized run. |
| **CMD-02** | R11,R23 | I/S/D | `NOT_RUN_DEVICE` | על F01 חדש ומבודד לכל שורה: program=cat, arguments=['sample.txt']. | alpha\nbeta\nalpha\n; exit code 0. |  |
| **CMD-03** | R11,R23 | I/S/D | `NOT_RUN_DEVICE` | על F01 חדש ומבודד לכל שורה: program=cp, arguments=['sample.txt','copy.txt']. | copy.txt שווה byte-for-byte למקור; exit code 0. |  |
| **CMD-04** | R11,R23 | I/S/D | `NOT_RUN_DEVICE` | על F01 חדש ומבודד לכל שורה: program=curl, arguments=['${FIXTURE_BASE}/ok.json']. | JSON עם marker=HANLIN_OK ו־answer=42; exit code 0. |  |
| **CMD-05** | R11,R23 | I/S/D | `NOT_RUN_DEVICE` | על F01 חדש ומבודד לכל שורה: program=grep, arguments=['alpha','sample.txt']. | alpha\nalpha\n; exit code 0. |  |
| **CMD-06** | R11,R23 | I/S/D | `NOT_RUN_DEVICE` | על F01 חדש ומבודד לכל שורה: program=head, arguments=['-n','1','sample.txt']. | alpha\n; exit code 0. |  |
| **CMD-07** | R11,R23 | I/S/D | `NOT_RUN_DEVICE` | על F01 חדש ומבודד לכל שורה: program=ln, arguments=['-s','sample.txt','sample-link']. | sample-link הוא symlink אל sample.txt; exit code 0. |  |
| **CMD-08** | R11,R23 | I/S/D | `NOT_RUN_DEVICE` | על F01 חדש ומבודד לכל שורה: program=ls, arguments=['.']. | הרשימה כוללת sample.txt ו־numbers.txt, ללא דרישת סדר בלתי מובטחת; exit code 0. |  |
| **CMD-09** | R11,R23 | I/S/D | `NOT_RUN_DEVICE` | על F01 חדש ומבודד לכל שורה: program=mkdir, arguments=['new-dir']. | new-dir קיים והוא directory; exit code 0. |  |
| **CMD-10** | R11,R23 | I/S/D | `NOT_RUN_DEVICE` | על F01 חדש ומבודד לכל שורה: program=mv, arguments=['copy.txt','moved.txt']. | מכין copy.txt מראש; moved.txt קיים ו־copy.txt אינו קיים; exit code 0. |  |
| **CMD-11** | R11,R23 | I/S/D | `NOT_RUN_DEVICE` | על F01 חדש ומבודד לכל שורה: program=readlink, arguments=['sample-link']. | sample.txt (ייתכן newline לפי הפקודה); exit code 0. |  |
| **CMD-12** | R11,R23 | I/S/D | `NOT_RUN_DEVICE` | על F01 חדש ומבודד לכל שורה: program=rm, arguments=['moved.txt']. | מכין moved.txt מראש; הקובץ הוסר והמקור נשמר; exit code 0. |  |
| **CMD-13** | R11,R23 | I/S/D | `NOT_RUN_DEVICE` | על F01 חדש ומבודד לכל שורה: program=rmdir, arguments=['empty-dir']. | מכין empty-dir ריקה; התיקייה הוסרה; exit code 0. |  |
| **CMD-14** | R11,R23 | I/S/D | `NOT_RUN_DEVICE` | על F01 חדש ומבודד לכל שורה: program=sed, arguments=['s/alpha/A/','sample.txt']. | A\nbeta\nA\n; exit code 0. |  |
| **CMD-15** | R11,R23 | I/S/D | `NOT_RUN_DEVICE` | על F01 חדש ומבודד לכל שורה: program=sort, arguments=['numbers.txt']. | 1\n2\n3\n; exit code 0. |  |
| **CMD-16** | R11,R23 | I/S/D | `NOT_RUN_DEVICE` | על F01 חדש ומבודד לכל שורה: program=stat, arguments=['-f','%z','sample.txt']. | הערך המספרי 17; exit code 0. |  |
| **CMD-17** | R11,R23 | I/S/D | `NOT_RUN_DEVICE` | על F01 חדש ומבודד לכל שורה: program=tail, arguments=['-n','1','sample.txt']. | alpha\n; exit code 0. |  |
| **CMD-18** | R11,R23 | I/S/D | `NOT_RUN_DEVICE` | על F01 חדש ומבודד לכל שורה: program=tar, arguments=['-cf','fixture.tar','sample.txt']. | archive קיים; רשימת entries וחילוץ מחזירים sample.txt עם אותם bytes; exit code 0. |  |
| **CMD-19** | R11,R23 | I/S/D | `NOT_RUN_DEVICE` | על F01 חדש ומבודד לכל שורה: program=touch, arguments=['touched.txt']. | קובץ touched.txt קיים; exit code 0. |  |
| **CMD-20** | R11,R23 | I/S/D | `NOT_RUN_DEVICE` | על F01 חדש ומבודד לכל שורה: program=tr, arguments=['a-z','A-Z']; stdin='alpha\nbeta\n'. | ALPHA\nBETA\n; exit code 0. |  |
| **CMD-21** | R11,R23 | I/S/D | `NOT_RUN_DEVICE` | על F01 חדש ומבודד לכל שורה: program=uniq, arguments=[]; stdin='alpha\nalpha\nbeta\n'. | alpha\nbeta\n; exit code 0. |  |
| **CMD-22** | R11,R23 | I/S/D | `NOT_RUN_DEVICE` | על F01 חדש ומבודד לכל שורה: program=unlink, arguments=['sample-link']. | הלינק הוסר; sample.txt המקורי נשמר; exit code 0. |  |
| **CMD-23** | R11,R23 | I/S/D | `NOT_RUN_DEVICE` | על F01 חדש ומבודד לכל שורה: program=wc, arguments=['-l','sample.txt']. | שדה count הוא 3; אל תשווה whitespace של BSD; exit code 0. |  |
| **NPM-01** | R14 | I/S | `REUSED_VERIFIED_PASS` | התקן F04 CJS ו־ESM דרך manager אמיתי. | list מציג שתי גרסאות 1.0.0; execution מחזיר 42; אין scanner veto. |  |
| **NPM-02** | R14 | I/S | `REUSED_VERIFIED_PASS` | package מכיל comment/string על sudo/docker/child_process. | התקנה וריצה רגילה מצליחות; אין סריקת מקור כ־security. |  |
| **NPM-03** | R14 | I/S | `REUSED_VERIFIED_PASS` | package כולל binding.gyp ו־.node בדוגמה שלא נטענת. | מותקן; metadata מזהה assets בלי להכריז unsupported לכל החבילה. |  |
| **NPM-04** | R14 | I/S/D | `NOT_RUN_DEVICE` | התקן hanlin-fixture-lifecycle והריץ את הפונקציה שקוראת generated.json. | lifecycle JS רץ in-process ויוצר generated=42; אין approval gate. |  |
| **NPM-05** | R14 | I/S | `REUSED_VERIFIED_PASS` | התקן את אותו package version עם שינוי lifecycle חוקי והפעל update. | הפעולה המבוקשת מתבצעת בלי exact-hash approval חדש; generation ותוצאה מעודכנים. |  |
| **NPM-06** | R14,R22 | I/S | `REUSED_VERIFIED_PASS` | lifecycle-fail יוצא ב־7. | stage/action/exit 7 נרשמים; אין installed-ready כוזב; גרסה קודמת נשמרת. |  |
| **NPM-07** | R14 | I/S | `REUSED_VERIFIED_PASS` | lifecycle דורש command שאינו linked או /bin/sh שלא זמין. | כשל יכולת ספציפי או adapter ממומש; לא ignore שקט ולא host crash. |  |
| **NPM-08** | R14 | I/S | `REUSED_VERIFIED_PASS` | package CLI-only ו־package subpath-only ללא root export. | מותקנים; probe אינו מבטל התקנה תקינה; CLI/subpath האמיתיים נבדקים. |  |
| **NPM-09** | R14 | I | `REUSED_VERIFIED_PASS` | dependency graph עם optional dependency שאינו נתמך ב־target. | semantics של manager נשמרים; package usable אינו נדחה רק בגלל optional asset. |  |
| **NPM-10** | R14 | I | `REUSED_VERIFIED_PASS` | registry fixture ללא integrity metadata. | מצב unverified עם content identity מקומי; לא חסימת אמון בלבד. |  |
| **NPM-11** | R14,R22 | I | `REUSED_VERIFIED_PASS` | registry מכריז digest אך מחזיר bytes אחרים. | לא מסומן verified; mismatch גלוי; אין stale identity או שינוי שקט בגרסה. |  |
| **NPM-12** | R14,R16 | I/S | `REUSED_VERIFIED_PASS` | התקן tgz ממקור local file ומ־HTTP fixture. | שני המסלולים עובדים לפי פורמט אמיתי; אין HTTPS-only gate. |  |
| **NPM-13** | R14,R22 | I | `REUSED_VERIFIED_PASS` | בטל install בזמן download ואז בזמן lifecycle; נסה התקנה חוזרת. | אין orphan state; retry פועל; משאבים קודמים לא נמחקים. |  |
| **NPM-14** | R14,R18 | I | `REUSED_VERIFIED_PASS` | package tree מעל תקרת count/size הישנה, עם fixtures קטנים ורבים. | אין cutoff שרירותי; רשום גודל מלא ותוצאה. |  |
| **NPM-15** | R14 | S/D | `NOT_RUN_DEVICE` | הרץ גם fixtures הציבוריים שהריפו כבר מצמיד: is-number@7.0.0, yocto-queue@1.2.2. | נבדקת ריצה אמיתית; registry outage הוא BLOCKED_EXTERNAL/FAIL נפרד, לא החלפת גרסה שקטה. |  |
| **PY-01** | R15 | I/S/D | `NOT_RUN_DEVICE` | התקן hanlin_fixture_py מתוך F04 wheel וייבא אותו. | answer=42; interpreter ו־site-packages הם של האפליקציה. |  |
| **PY-02** | R15 | I/S | `NOT_RUN` | distribution בשם שונה מה־import name. | התקנה תקינה אינה נכשלת בגלל הנחת name.replace('-', '_'); import הנכון עובד. | Semantic test implementation updated on current HEAD; pending authorized run. |
| **PY-03** | R15 | I/S | `REUSED_VERIFIED_PASS` | wheel עם .data/purelib ומודול שמועבר לנתיב import. | מודול נגיש; data layout מיושם ולא נשאר רק directory zip. |  |
| **PY-04** | R15 | I/S | `REUSED_VERIFIED_PASS` | wheel עם .pth חוקי שמוסיף subdirectory שבו module answer=42. | activation לפי semantics מתועדים; אין איסור גורף על .pth. |  |
| **PY-05** | R15 | I/S | `REUSED_VERIFIED_PASS` | wheel עם .wasm/.bin/assets שלא נטענים כ־native extension. | הנתונים מותקנים; אין suffix/magic scanner veto. |  |
| **PY-06** | R15 | I | `REUSED_VERIFIED_PASS` | wheel tag תואם runtime שאינו בדיוק py3-none-any. | resolver מתאים לפי tags אמיתיים; אין מסנן יחיד קשיח. |  |
| **PY-07** | R15 | I/S | `REUSED_VERIFIED_PASS` | wheel עם ABI/architecture לא־תואמים. | שגיאת התאמה מדויקת בעת שימוש/התקנה לפי contract; אין טענת import מוצלח. |  |
| **PY-08** | R15 | I/S | `REUSED_VERIFIED_PASS` | pure-Python sdist עם build backend המקומי של F04. | נוצר wheel/תוצר התקנה אמיתי ואז import=42; לא רק ביטול guard. |  |
| **PY-09** | R15 | I/S | `REUSED_VERIFIED_PASS` | sdist שדורש compiler/מערכת build שאינם מוטמעים. | backend/toolchainUnavailable עם הצעד המדויק; אין מצג של תמיכה מלאה. |  |
| **PY-10** | R15 | I | `REUSED_VERIFIED_PASS` | 66 dependencies מקומיות וקטנות בשרשרת. | כל התלויות נפתרות ומותקנות; אין safety limit של 64. |  |
| **PY-11** | R15 | U/I | `REUSED_VERIFIED_PASS` | dependency cycle ו־version constraints סותרים בשני fixtures. | cycle אינו רקורסיה אינסופית; conflict אמיתי מדווח, בלי false success. |  |
| **PY-12** | R15,R18 | I/S | `REUSED_VERIFIED_PASS` | wheel מעל 100MiB עם נתון deterministic גדול. | streaming install ללא max 100MB; marker/hash מלאים; אין RAM spike של archive כולו. |  |
| **PY-13** | R15 | U/I | `REUSED_VERIFIED_PASS` | markers של python_version/sys_platform עם extras שונים. | רק dependencies המתאימות מותקנות; extras שנבחרו אינם נזרקים גורפית. |  |
| **PY-14** | R15 | U/I | `REUSED_VERIFIED_PASS` | versions 1.9, 1.10, pre-release ו־~= ב־fixture registry. | פתרון לפי semantics packaging, לא השוואת substring שרירותית. |  |
| **PY-15** | R15,R16 | I | `REUSED_VERIFIED_PASS` | artifact ממirror/local source שהמשתמש בחר, ולא רק pypi.org/pythonhosted. | המקור נתמך דרך מסלול אמיתי; אין hostname allowlist כמדיניות. |  |
| **PY-16** | R15 | I | `REUSED_VERIFIED_PASS` | package ש־import שלו צריך configuration או שאין לו import root. | installed נשמר עם probe status נפרד; אין rollback על ניחוש שגוי. |  |
| **PY-17** | R15,R22 | I | `REUSED_VERIFIED_PASS` | wheel קטוע, metadata לא־קריא ו־write failure. | כשל תקינות אמיתי; transaction/registry נשארים עקביים. |  |
| **PY-18** | R15 | I/S/D | `NOT_RUN_DEVICE` | restart של האפליקציה אחרי install; import מחדש; uninstall; import שוב. | לפני uninstall import עובד, אחריו נכשל כ־module missing; תלות של package אחר לא נעלמת. |  |
| **PY-19** | R15,R22 | I/S | `REUSED_VERIFIED_PASS` | Python probe/execute ו־shell פועלים במקביל; inject cancellation. | GIL/cwd/streams עקביים; אין deadlock ושאר האפליקציה ממשיכה. |  |
| **PY-20** | R15 | S/D | `NOT_RUN_DEVICE` | הרץ fixture הציבורי המוצמד בריפו requests==2.34.2 רק אם registry מאמת שקיים. | תוצאת רשת והתקנה אמיתית מתועדות; חוסר גרסה/רשת אינו מוחלף בשקט ואינו PASS. |  |
| **CAP-01** | R17 | I/S | `REUSED_VERIFIED_PASS` | local package ללא רשומות grants מפעיל files/storage/network/assistant על fixture. | אין missingGrant/default-deny של Hanlin במסלול האישי. |  |
| **CAP-02** | R17 | I/S | `REUSED_VERIFIED_PASS` | אותו package דרך ScriptUI, NativeScript, Expo ו־compiled MiniApp adapters, ככל שהמסלול קיים. | אין broker צדדי שמחזיר policy denied; תוצאות היכולות זהות. |  |
| **CAP-03** | R17 | I/S | `REUSED_VERIFIED_PASS` | ה־authority מאפשר פעולה אך session נוצר קודם עם filesAllowed=false. | מצב אישי עקבי; אין Boolean ישן שמשאיר את החסימה פעילה. |  |
| **CAP-04** | R17 | I/S | `REUSED_VERIFIED_PASS` | הפעל provider localUnverified/minimumTrust בלי אישור אמון נפרד. | התקנה/רישום מבוצעים; אין trust review gate חדש. |  |
| **CAP-05** | R17 | I/S | `REUSED_VERIFIED_PASS` | המשתמש כיבה tool group או app בהגדרה קיימת. | המצב מכובד; אין auto-grant/auto-enable שמבטלים את בחירתו. |  |
| **CAP-06** | R17,R21 | S/D | `NOT_RUN_DEVICE` | מצבי OS notDetermined/authorized/denied עבור Camera/Microphone/Contacts/Location. | prompt מערכת במקום הנכון; denied מתועד כהחלטת OS, לא מוסתר או עוקף. |  |
| **CAP-07** | R17,R21 | S/D | `NOT_RUN_DEVICE` | Health/Calendar/Reminders זמינים מול target שאינו תומך או OS authorization denied. | unavailable/denied/no data מובחנים; אין נתונים מומצאים. |  |
| **CAP-08** | R17 | I/S | `REUSED_VERIFIED_PASS` | openURL ללא userGesture יישומי כאשר host API מאפשר זאת. | אין gate פרטי נוסף; תוצאת OS אמיתית נשמרת. |  |
| **CAP-09** | R17,R22 | I/S | `REUSED_VERIFIED_PASS` | בקשת UI מתוך context ללא foreground scene, ואחריה מתוך scene פעיל. | delegation/שגיאת context מדויקת; כשה־scene פעיל הפעולה מוצגת. |  |
| **CAP-10** | R21 | U/I | `REUSED_VERIFIED_PASS` | Health fixture על פני 2 שנים ו־601 workouts, עם pagination. | אין תקרת שנה/500 של Hanlin; כל הרשומות מתקבלות בלי truncation שקט. |  |
| **CAP-11** | R21 | U/I | `REUSED_VERIFIED_PASS` | Health sort נוסף שה־API/transport תומך בו. | sort אינו נדחה כי אינו descriptor יחיד hardcoded; סדר תוצאות נכון. |  |
| **CAP-12** | R21 | U/I | `REUSED_VERIFIED_PASS` | Notification/reminder text ו־arrays מעל caps הפנימיים הישנים. | הקלט עובר כאשר backend תומך; מגבלת backend אמיתית מדווחת ספציפית. |  |
| **CAP-13** | R21,R22 | U/I | `REUSED_VERIFIED_PASS` | NaN/תאריך לא־תקין/end לפני start/enum לא־קיים. | validation טכני נשאר; אין side effect invalid ואין קריסה. |  |
| **CAP-14** | R17,R22 | I/S | `REUSED_VERIFIED_PASS` | legacy grants store ו־app IDs מהתקנה קודמת לאחר migration. | נתונים נשמרים; הפיתוח האישי עובד בלי צורך לאפס registry. |  |
| **NET-01** | R16 | I/S/D | `BLOCKED_EXTERNAL` | Skill download מ־HTTP fixture ו־HTTPS fixture. | אין Hanlin HTTPS-only; תוצאת backend/ATS נרשמת במדויק. |  |
| **NET-02** | R16 | I/S | `BLOCKED_EXTERNAL` | 7 redirects מ־F03 שמסתיימים ב־ok.json. | אין תקרת 5 הישנה; marker מתקבל. |  |
| **NET-03** | R16,R22 | I | `REUSED_VERIFIED_PASS` | redirect loop בין /loop-a ו־/loop-b ואז cancel. | אין המתנה אינסופית; loop/cancel outcome מפורש, בלי סריקת URL נוספת. |  |
| **NET-04** | R16,R18 | I/S | `REUSED_VERIFIED_PASS` | response של 20MiB+17 bytes מ־/large. | כל bytes נשמרים/נגישים; אין max 8/16MB שקט. |  |
| **NET-05** | R16 | I/S | `REUSED_VERIFIED_PASS` | 404/500/TLS certificate error בכל אחד ממסלולי download. | ה־status/שגיאת TLS נשמרים; אין disabled TLS verification. |  |
| **NET-06** | R16 | S/D | `NOT_RUN_DEVICE` | localhost/LAN access דרך מסלול Apple network האמיתי. | הגדרות ATS/Local Network מתאימות; backend error אינו מיוחס לסורק של Hanlin. |  |
| **NET-07** | R16,R24 | I | `REUSED_VERIFIED_PASS` | URL/header כולל secret fixture; server recorder מאשר קבלה. | הבקשה מתבצעת, אבל secret לא מופיע בלוג המודל/דוח ציבורי. |  |
| **NET-08** | R16,R18 | I/S | `REUSED_VERIFIED_PASS` | download איטי מעל timeout ישן, עם timeout=null/מורחב ואז cancel. | אין hard clamp ישן; cancel מסיים ו־cleanup תקין. |  |
| **LIM-01** | R18 | U/I | `REUSED_VERIFIED_PASS` | timeout=601 שניות נבנה ומועבר ל־backend; השתמש fake clock לבדיקת גבול. | הערך אינו נחתך ל־300; serialized config משקף 601. |  |
| **LIM-02** | R18 | I/S | `REUSED_VERIFIED_PASS` | ריצה אמיתית bounded מעבר ל־30s תחת timeout מורחב. | אין worker cutoff הישן; ריצה משלימה או error אמיתי. |  |
| **LIM-03** | R18 | I/S | `REUSED_VERIFIED_PASS` | פלט מעל 8MB עם START_42 ו־END_42. | פלט מלא נשמר מאחורי reference; המודל מקבל דרך גישה, לא 8MB truncation. |  |
| **LIM-04** | R18 | I/S | `REUSED_VERIFIED_PASS` | 51 תוצאות ו־total payload מעל 10MB תחת config מתאים. | אין eviction מאבד־מידע בלתי מדווח; references תקינים לפי lifetime המוגדר. |  |
| **LIM-05** | R18 | U/I | `REUSED_VERIFIED_PASS` | read_tool_result בפרוסות מעל 16KB ומכל offset לאורך UTF-8 Hebrew/emoji. | אין cap ישן; שחזור bytes מדויק ללא פגיעה בתווי UTF-8. |  |
| **LIM-06** | R18 | U/I | `REUSED_VERIFIED_PASS` | configure limits=null ו־limits מפורשים; בדוק overflow/negative inputs. | אין שימוש מסוכן ב־Int.max; semantics ברורים ו־validation טכני. |  |
| **LIM-07** | R18 | I/S | `REUSED_VERIFIED_PASS` | QuickJS workload מעל 16MB הישנים תחת memory limit מורחב. | אין hardcoded 16MB; קוד מחזיר marker או engine error אמיתי. |  |
| **LIM-08** | R18 | U/I | `REUSED_VERIFIED_PASS` | רשום callbacks/promises/events מעבר ל־caps הישנים עם config מורחב. | אין דחייה ישנה; disposal משחרר את כל המשאבים. |  |
| **LIM-09** | R18,R22 | I/S | `REUSED_VERIFIED_PASS` | cancel Node/Python task ואז הרץ task תקין חדש. | החדש פועל; אין zombie completion או host stuck. |  |
| **LIM-10** | R18 | I/S | `REUSED_VERIFIED_PASS` | JSC sync task לא־ניתן להפרעה במנגנון הנוכחי — בדיקה bounded בלבד. | הדיווח אינו מציג timer חיצוני כ־hard cancel; אין infinite loop במכשיר המשתמש. |  |
| **LIM-11** | R18,R22 | I | `REUSED_VERIFIED_PASS` | disk-full fixture בעת שמירת large result. | כשל שמירה ברור; אין reference לתוכן שלא נשמר; אין memory fallback בלתי מוגבל. |  |
| **LIM-12** | R18,R24 | I/S | `REUSED_VERIFIED_PASS` | סיים run/פתח saved chat ונסה reference לפי lifetime שפורסם. | תוכן נגיש או expiration מפורש לפי contract; אין UI שמציג reference מת כתוצאה זמינה. |  |
| **APP-01** | R19 | U/I/S | `REUSED_VERIFIED_PASS` | source עם comment ומחרוזת הכוללים import, eval, process או sudo. | אין analyzer veto של מילים שאינן פעולה. |  |
| **APP-02** | R19 | I/S | `REUSED_VERIFIED_PASS` | package רב־קבצי עם relative modules, JSON ו־bare dependency מקומי זמין. | resolver/bundler אמיתי מספק dependencies; app/tool מחזירים 42. |  |
| **APP-03** | R19 | I/S | `REUSED_VERIFIED_PASS` | bare dependency חסר, ובנפרד syntax/type error אמיתי. | כשל compiler/resolver מדויק; לא policy message ולא fake install-ready. |  |
| **APP-04** | R19 | I/S | `REUSED_VERIFIED_PASS` | warning analyzer בלבד מול compilation מוצלח. | warning אינו חוסם canInstall; התוצר פועל. |  |
| **APP-05** | R20 | I/S/D | `NOT_RUN_DEVICE` | NativeScript pure-JS plugin בעל שם שלא ברשימה הישנה אך עם backend נתמך. | אין plugin-name veto; UI/handler באמת פועלים. |  |
| **APP-06** | R20 | I/S/D | `NOT_RUN_DEVICE` | plugin הדורש native provider מוטמע מוכר, ולאחר מכן provider חסר. | המוכר עובד; החסר מדווח ברמת dependency/platform, לא מוצג כתמיכה. |  |
| **APP-07** | R20 | U/I/S | `REUSED_VERIFIED_PASS` | גרסה בתוך טווח תאימות backend מוכח וגרסה עם ABI לא־נתמך. | התואמת מתקבלת; אי־תאימות אמיתית אינה נבלעת. |  |
| **APP-08** | R20 | I/S/D | `NOT_RUN_DEVICE` | פתח/סגור/פתח NativeScript ו־Expo, כולל מעבר בין שתי sessions. | אין leak או crash; מגבלת session אמיתית מטופלת ולא נמחקת כ־guard בלבד. |  |
| **APP-09** | R20 | I/S | `REUSED_VERIFIED_PASS` | פרסם tool של Script package, גלה דרך Skill והרץ דרך canonical authority. | אותו logicalID/backend; אין stub service או alias לא־קיים. |  |
| **APP-10** | R20,R23 | I/S/D | `NOT_RUN_DEVICE` | החזר embedded result מסוג Swift/ScriptUI/NativeScript/Expo לפי התמיכה הקיימת. | כל renderer הנתמך נפתח ומקבל payload; חסר מסוים מפורש ולא success ריק. |  |
| **APP-11** | R20 | S/D | `NOT_RUN_DEVICE` | widget/App Intent/Live Activity של fixture ב־target המתאים. | ביצוע דרך target/bridge אמיתיים; אין טעינת foreground-only runtime בכוח. |  |
| **APP-12** | R22 | I/S | `REUSED_VERIFIED_PASS` | ערוך source חוקי ועדכן package; הפעל לאחר relaunch. | artifact generation חדש פועל; לא stale code ולא security rejection. |  |
| **APP-13** | R22 | I | `REUSED_VERIFIED_PASS` | artifact digest לא־תואם או registry קטוע אחרי crash מוזרק. | rebuild/recovery/rollback לפי contract; אין סימון corrupt bytes כ־verified. |  |
| **APP-14** | R22 | I/S | `REUSED_VERIFIED_PASS` | install/update/uninstall עם שני packages ונתוני משתמש קיימים. | identity ונתוני האחר נשמרים; migration אינו מאפס storage. |  |
| **FUNC-01** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | quick_calculate: {"expression":"(12+8)*3"}. | result 60; card ו־modelText מסכימים; קריאת calculator אמיתית. |  |
| **FUNC-02** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | quick_calculate: {"expression":"1/0"}. | outcome failed ו־division-by-zero; לא success עם טקסט Calculation failed. |  |
| **FUNC-03** | R06,R23 | I/S/D | `NOT_RUN_DEVICE` | execute_local_python_code: {"source":"import json; print(json.dumps({'answer':sum(i*i for i in range(1,101))}))"}. | stdout JSON answer=338350; runtime localPython; אין fallback remote. |  |
| **FUNC-04** | R06,R23 | I/S/D | `NOT_RUN_DEVICE` | execute_javascript_code: {"source":"console.log(6*7)","runtime":"node"}. | stdout 42; Node מופעל. |  |
| **FUNC-05** | R06,R23 | I/S/D | `NOT_RUN_DEVICE` | execute_typescript_code: {"source":"const n:number=42; console.log(n)","compile_only":false}. | compiler ו־Node אמיתיים; output 42. |  |
| **FUNC-06** | R06,R23 | I/S/D | `NOT_RUN_DEVICE` | execute_shell_command במצב argv: program=cat, arguments=["sample.txt"]. | תוכן F01 אמיתי; אין pretend shell. |  |
| **FUNC-07** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | save_memory: {"content":"HANLIN_TEST_MEMORY answer 42"} בפרופיל ריק. | רשומה אחת נשמרת; store test בלבד. |  |
| **FUNC-08** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | retrieve_memory: {"keyword":"HANLIN_TEST_MEMORY"} אחרי FUNC-07. | נמצא התוכן המדויק, לא הסקת מודל. |  |
| **FUNC-09** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | update_memory: {"originalContent":"HANLIN_TEST_MEMORY answer 42","updatedContent":"HANLIN_TEST_MEMORY answer 43"}; retrieve מחדש. | התוכן החדש קיים, הישן אינו מוכפל; mismatch של original מדווח. |  |
| **FUNC-10** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | search_calendar_and_reminders: {"start_date":"2030-01-15","end_date":"2030-01-15","event_type":"calendar"} על F05. | נמצא Hanlin Fixture Meeting; TZ לפי test clock; no live calendar writes. |  |
| **FUNC-11** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | write_system_event: {"type":"calendar","title":"HANLIN_TEST_NEW","start_date":"2030-01-15T12:00:00+00:00","end_date":"2030-01-15T12:30:00+00:00"} על F05 ואז search. | אירוע יחיד עם שעות מדויקות; no duplicate side effect. |  |
| **FUNC-12** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | write_system_event: {"type":"reminder","title":"HANLIN_TEST_REMINDER","due_date":"2030-01-15T13:00:00+00:00","notes":"Fixture only"} ואז search reminders. | תזכורת אחת עם due date תואם; test store בלבד. |  |
| **FUNC-13** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | query_location: {"keyword":"Hanlin Fixture Place"} כאשר transport מחזיר F05 A. | lat=31.778, lon=35.235; לא geocoding מהזיכרון. |  |
| **FUNC-14** | R06,R23 | I/S/D | `NOT_RUN_DEVICE` | get_current_location: {"query":"local"} עם location fixture; ב־device השתמש בהרשאת OS קיימת/בדיקת deny. | fixture A או status OS אמיתי; אין המצאת מיקום. |  |
| **FUNC-15** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | search_nearby_locations: {"coordinate":{"latitude":31.778,"longitude":35.235},"keyword":"fixture"} על F05. | POI list מה־fixture בלבד; השאילתה מתועדת ב־transport. |  |
| **FUNC-16** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | get_route: {"start":{"latitude":31.778,"longitude":35.235},"end":{"latitude":31.780,"longitude":35.240},"mode":"walking"} על F05. | distance 900/duration 720 כפי שה־fixture מגדיר; units נשמרים. |  |
| **FUNC-17** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | query_weather: {"latitude":31.778,"longitude":35.235,"timeRange":"now"} על F05. | 21°C + fixture marker; אין תחזית מומצאת במקרה backend error. |  |
| **FUNC-18** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | search_online: {"query":"HANLIN_WEB_MARKER"} דרך transport fixture. | תוצאת search fixture עם URL מזוהה; אין remote search לא־נדרש. |  |
| **FUNC-19** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | read_web_page: {"url":"${FIXTURE_BASE}/page.html"}. | גוף מכיל HANLIN_WEB_MARKER; URL ועקבות הקריאה תואמים. |  |
| **FUNC-20** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | search_arxiv_papers: {"query":"Hanlin Fixture Paper"} עם Atom feed F03. | כותרת/ID fixture מוחזרים; no-match/HTTP failure אינם מקבלים papers מומצאים. |  |
| **FUNC-21** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | extract_remote_file_content: {"url":"${FIXTURE_BASE}/document.txt"}; צור body=HANLIN_FILE_MARKER. | הטקסט המדויק חולץ; אותו תרחיש מורחב ל־PDF/DOCX/XLSX אם extractor מפרסם תמיכה בהם. |  |
| **FUNC-22** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | search_knowledge_bag: {"query":"HANLIN_KNOWLEDGE_MARKER"} על bag fixture. | מסמך fixture עם answer 42; אין מעבר לשירות web במקום מקומי. |  |
| **FUNC-23** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | create_knowledge_document: {"title":"Hanlin Fixture","content":"# Fixture\nHANLIN_CREATED_DOC 42"} ואז חיפוש. | המסמך נשמר ונמצא; content מלא. |  |
| **FUNC-24** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | create_canvas: {"title":"Hanlin Fixture","content":"alpha beta","type":"text"}. | Canvas אמיתי עם title/content נכונים. |  |
| **FUNC-25** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | edit_canvas: {"patterns":["beta"],"replacements":["gamma"]} אחרי FUNC-24. | Canvas מציג alpha gamma; pattern invalid/arrays length mismatch -> error אמיתי. |  |
| **FUNC-26** | R06,R23 | I/S/D | `NOT_RUN_DEVICE` | create_web_view: {"code":"<!doctype html><meta name='viewport' content='width=device-width'><button onclick=\"this.textContent='42'\">Run</button>"}. | preview נטען; tap משנה לכיתוב 42; לא קוד טקסטואלי במקום UI. |  |
| **FUNC-27** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | execute_remote_python_code: {"code":"print(6*7)"} דרך remote transport fixture בלבד. | request נשלח ל־remote executor המוגדר ותוצאה 42 מסומנת remote; אין החלפה שקטה של local. |  |
| **FUNC-28** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | fetch_step_details: {"start_date":"2026-10-01","end_date":"2026-10-01"} על Health F05. | 1,234 steps, units/time buckets מתאימים; unavailable אינו אפס. |  |
| **FUNC-29** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | fetch_energy_details עם אותם date fields על F05. | active energy=56 kcal; המרת יחידות נכונה. |  |
| **FUNC-30** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | fetch_nutrition_details עם אותם date fields על F05. | values/buckets של nutrition fixture מוחזרים בדיוק. |  |
| **FUNC-31** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | make_nutrition_data: {"protein":10,"carbohydrates":20,"fat":5,"energy":165}. | נוצר nutrition card עם אותם values. אין טענה שכבר נכתב ל־Health אם נדרשת פעולת UI נפרדת. |  |
| **FUNC-32** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | sefaria_search: {"query":"Hanlin fixture","limit":2} דרך F05. | שתי תוצאות fixture עם ref/snippet; error/no results אינם מושלמים מזיכרון. |  |
| **FUNC-33** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | sefaria_get_source: {"ref":"Genesis 1:1"} דרך F05. | ref וטקסט בדיוק כמו response fixture; copy/open actions מצביעים לאותו source. |  |
| **FUNC-34** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | wikipedia_search: {"query":"Jerusalem","language":"he","limit":2} דרך F05. | שתי תוצאות fixture בעברית; language נשמר ל־open action. |  |
| **FUNC-35** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | wikipedia_get_summary: {"title":"Jerusalem","language":"en"} דרך F05. | summary fixture בלבד; error outcome אינו .succeeded. |  |
| **FUNC-36** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | text_analyze: {"text":"alpha beta"}. | Characters=10, Words=2; בדוק גם Unicode לפי semantics המוצהרים. |  |
| **FUNC-37** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | text_transform: text="Alpha beta", transform=ערך enum אמיתי של uppercase מה־schema. | ALPHA BETA; ערך transform לא־קיים מחזיר failed/invalidArguments. |  |
| **FUNC-38** | R06,R23 | I/S | `REUSED_VERIFIED_PASS` | הרץ את החוזה הפרמטרי מסעיף 4.3 על כל tool נוסף: aliases legacy, MCP, Script ו־compiled providers. | אין published tool בלי תסריט; אין ספירת רישום בלבד כהצלחת execution. |  |
| **UI-01** | R02,R03,R06 | S/D | `NOT_RUN_DEVICE` | Import pack מתוך Files -> preview -> install -> Skill Center -> details. | כל הפריטים מוצגים עם metadata נכון; אין שגיאת staging/תאריך. |  |
| **UI-02** | R04,R06 | S/D | `NOT_RUN_DEVICE` | ערוך Skill, שמור, export, מחק רק את fixture וייבא מחדש. | body/metadata/resources נשמרים; ניתן לטעון את אותו Skill. |  |
| **UI-03** | R23,R24 | S/D | `NOT_RUN_DEVICE` | הרץ tool מצליח, tool כושל ו־cancel; פתח Agent Activity. | סטטוסים, אייקון/טקסט, backend ו־result תואמים; אין success card לכשל. |  |
| **UI-04** | R23 | S/D | `NOT_RUN_DEVICE` | פתח result card, בצע copy/open route ואז חזור לשיחה. | הפעולה משתמשת ב־payload הנכון; שיחה וריצה אינן מתאפסות. |  |
| **UI-05** | R23 | S/D | `NOT_RUN_DEVICE` | בדוק עברית RTL, split view צר/רחב, rotation ו־Dynamic Type. | כפתורי install/cancel ו־tool result נגישים; אין clipping שמונע בדיקה. |  |
| **UI-06** | R18,R22 | S/D | `NOT_RUN_DEVICE` | ריצה ארוכה ברקע/foreground וחזרה; לאחר מכן בקשה חדשה. | state משקף התנהגות OS בפועל; אין הבטחה לריצה אינסופית ברקע ואין orphan spinner. |  |
| **PROV-01** | R05,R06,R24 | P/D | `BLOCKED_EXTERNAL` | במודל שהוגדר בפועל: 'הרץ בפייתון מקומי חיבור ריבועי המספרים 1 עד 100 והראה את התוצאה'. | load_skill/discovery ואז local tool invocation; answer 338350 עם ToolResult אמיתי. |  |
| **PROV-02** | R05,R06,R08 | P/D | `BLOCKED_EXTERNAL` | 'התקן בסביבה המקומית את חבילת ה־fixture שהוגדרה לבדיקה והשתמש בה כדי להחזיר 42'. | Skill package/runtime, package tool ואז execution; לא 'אין לי אפשרות כי sandbox'. |  |
| **PROV-03** | R05,R11 | P/D | `BLOCKED_EXTERNAL` | 'צור קובץ עם שלוש שורות, וספור בטרמינל כמה שורות יש בו'. | פעולת כתיבה וכלי shell אמיתיים; count 3; אין ריצה פיקטיבית. |  |
| **PROV-04** | R05,R12 | P/D | `BLOCKED_EXTERNAL` | 'Run JavaScript with a timer, then print 42' וגם נוסח עברי שקול. | Node נבחר לפי workflow; פלט 42; JSC לא מוצג כתומך timers ללא backend. |  |
| **PROV-05** | R05,R06 | P/D | `BLOCKED_EXTERNAL` | 'קרא את הכתובת של דף הבדיקה וסכם מה כתוב בה'. | web Skill וכלי read אמיתי; הסיכום מבוסס marker fixture. |  |
| **PROV-06** | R05,R07 | P/D | `BLOCKED_EXTERNAL` | 'הראה לי את כל הכלים, ובדוק מי זמין ומי כבוי'. | enumeration עם pagination; אין טענה שרק עשרת תוצאות search הם כל הכלים. |  |
| **PROV-07** | R05,R24 | P | `BLOCKED_EXTERNAL` | לכל PROV-01..06: לפחות 3 שיחות חדשות באותו provider/model, ורשום request/model ID מדויקים. | מדווח pass count אמיתי מתוך ניסיונות; mock success לא מתחלף בו; rate limit/רשת מסומנים בנפרד. |  |
| **PROV-08** | R05,R23 | P | `BLOCKED_EXTERNAL` | הפעל failure fixture ואז בקשה לתיקון; אל תחליף ספק בלי לדווח. | המודל מפרש tool error מדויק ומבצע retry מתאים; אין המצאת יכולת או איבוד tools. |  |
| **BUILD-01** | R25 | B | `REUSED_VERIFIED_PASS` | הרץ בדיקות parser/codec/exposure/registry/contracts המקומיות שנוגעות לשינויים. | PASS לכולן; full command ו־exit code נשמרים. |  |
| **BUILD-02** | R25 | B | `REUSED_VERIFIED_PASS` | הרץ Node host tests ו־integration tests עם fixtures המקומיים. | אין source scanner/lifecycle policy regression; תוצאות אינן תלויות registry ציבורי. |  |
| **BUILD-03** | R25 | B | `REUSED_VERIFIED_PASS` | הרץ Swift package tests עבור targets ששונו, לפי סכמות שנמצאו בפועל. | compiler/test runner אמיתיים; לא static grep במקום tests. |  |
| **BUILD-04** | R25 | B/S | `NOT_RUN` | build-for-testing של app ו־test-without-building לקבוצות המושפעות. | הבדיקות רצות מתוך bundle ולא checkout fallback; xcresults נשמרים. |  |
| **BUILD-05** | R25 | B | `NOT_RUN` | Compile device target ו־simulator target עם toolchain הרלוונטי של הפרויקט. | אין הורדת deployment target או שינוי signing scope בלי צורך; warnings/errors מתועדים. |  |
| **BUILD-06** | R11,R25 | B/S | `REUSED_VERIFIED_PASS` | בדוק packaged command dictionaries/framework symbols/resource bundles. | כל command שפורסם באמת קיים; אין exact-23 check ישן. |  |
| **BUILD-07** | R13,R25 | B/S | `REUSED_VERIFIED_PASS` | בדוק RuntimeHostResources.zip שה־IPA בפועל אורז. | ה־JS המתוקן נמצא באריזה; אין עותק stale של rejectUnsafeSource או policies ישנים. |  |
| **BUILD-08** | R06,R25 | B/S | `REUSED_VERIFIED_PASS` | פתח כל Skill ZIP, פענח metadata באותו codec של האפליקציה וייבא באמצעות SkillImporter האמיתי. | כל packages תקינים; validator חיצוני בלבד אינו מספיק. |  |
| **BUILD-09** | R25,R26 | B/S/D | `NOT_RUN_DEVICE` | הפעל suite של existing tools/miniapps אחרי השינויים, כולל cold launch ו־relaunch. | אין regression במנגנונים קיימים; device results נפרדים ומקושרים ל־IPA SHA. |  |
| **BUILD-10** | R26 | U/B | `REUSED_VERIFIED_PASS` | השווה כל מזהי R/test/tool/restriction לדוח הסופי ו־git diff. | אין מזהה חסר; אין PASS ללא evidence; remaining blockers מפורטים בדיוק. |  |
| **SDKAI-01** | R27 | unit | `REUSED_VERIFIED_PASS` | Feed an OpenAI-compatible text-only fixture through the production provider mapping. | The selected model/provider is the Swift AI SDK provider; no legacy request builder is invoked. |  |
| **SDKAI-02** | R27 | unit | `REUSED_VERIFIED_PASS` | Feed OpenAI, Anthropic, Google/Gemini and OpenRouter/OpenAI-compatible configurations through provider resolution. | Each resolves to the intended SDK provider/base URL/model ID/headers without duplicate manual JSON construction. |  |
| **SDKAI-03** | R27 | integration | `REUSED_VERIFIED_PASS` | Stream `hello` from deterministic OpenAI-compatible fixture in 5 chunks. | Chunks surface once, in order; final content is `hello`; no duplicate event from old parser. |  |
| **SDKAI-04** | R27 | integration | `REUSED_VERIFIED_PASS` | Fixture emits provider reasoning delta + visible text. | Provider-surfaced reasoning and visible text remain separate and correctly presented; no hidden/private CoT is fabricated. |  |
| **SDKAI-05** | R27 | integration | `REUSED_VERIFIED_PASS` | Fixture emits usage fields including input/output/reasoning/cached tokens. | Usage maps to Hanlin diagnostics exactly once. |  |
| **SDKAI-06** | R27 | integration | `REUSED_VERIFIED_PASS` | Model calls deterministic `echo` tool, receives output, then writes final text. | Swift AI SDK performs tool loop; trace shows one tool execution and a later model step; final answer uses the tool result. |  |
| **SDKAI-07** | R27 | integration | `REUSED_VERIFIED_PASS` | Model calls two tools in one step. | Both calls execute with stable call IDs; results return to SDK; no legacy recursion handles them. |  |
| **SDKAI-08** | R27 | integration | `REUSED_VERIFIED_PASS` | Model calls a tool that returns typed error. | Tool error is delivered through SDK semantics, marked failed in diagnostics, and a subsequent model step can recover. |  |
| **SDKAI-09** | R27 | integration | `REUSED_VERIFIED_PASS` | `prepareStep` changes active tool schemas after `load_skill`. | Next SDK step sees newly exposed tools without rebuilding a second agent loop. |  |
| **SDKAI-10** | R27 | integration | `REUSED_VERIFIED_PASS` | Run more than 2 recursive tool steps but fewer than configured stop limit. | SDK continues correctly and does not terminate after one tool round. |  |
| **SDKAI-11** | R27 | integration | `REUSED_VERIFIED_PASS` | Deterministic fixture reaches configured maximum step count. | Run stops with explicit stop reason and no infinite recursion. |  |
| **SDKAI-12** | R27 | unit | `REUSED_VERIFIED_PASS` | Search production call graph after routing migration. | No tool-capable text provider calls the obsolete manual `finishReason == tool_calls` execution path. |  |
| **SDKAI-13** | R27,R43 | source/build | `REUSED_VERIFIED_PASS` | Remove dead manual tool-loop code and compile all app targets/tests. | No unresolved references; old loop is actually deleted, not just permanently disabled by an `if false`. |  |
| **SDKAI-14** | R27 | regression | `REUSED_VERIFIED_PASS` | Exercise image-generation path that is not owned by `streamText`. | Image generation still works or reports the same real provider limitation; it was not accidentally deleted. |  |
| **SDKAI-15** | R27 | regression | `REUSED_VERIFIED_PASS` | Exercise configured audio/voice generation path if supported by current model fixture. | Audio-specific behavior remains on its explicit path and does not pass through incompatible text SDK path. |  |
| **SDKAI-16** | R27 | regression | `REUSED_VERIFIED_PASS` | Exercise local LLM mode. | Local model remains local; no remote Swift AI SDK provider is selected. |  |
| **SDKAI-17** | R27 | provider | `REUSED_VERIFIED_PASS` | Real configured provider prompt: `Use the calculator/tool to compute 19*23, then answer with only the number.` | Tool trace exists and final answer is `437`; no fake computation without the tool when tool use was required by test harness. |  |
| **SDKAI-18** | R27 | provider | `REUSED_VERIFIED_PASS` | Real provider receives a tool error, then is asked to correct the arguments. | It can make a corrected second call in same SDK run. |  |
| **SDKFORK-01** | R28 | audit | `REUSED_VERIFIED_PASS` | Compare Hanlin fork against current `teunlao/swift-ai-sdk` upstream. | Every fork-only commit/file is listed in `swift-ai-sdk-patches.md` with rationale. |  |
| **SDKFORK-02** | R28 | unit/upstream | `REUSED_VERIFIED_PASS` | For each fork patch with an upstream equivalent, drop patch on a temporary branch and run relevant SDK tests. | Patch is removed only if upstream now passes the Hanlin regression. |  |
| **SDKFORK-03** | R28 | package | `REUSED_VERIFIED_PASS` | Resolve Hanlin against chosen immutable fork revision/tag. | SwiftPM resolves deterministically and app imports expected products. |  |
| **SDKFORK-04** | R28 | integration | `REUSED_VERIFIED_PASS` | Run Hanlin provider/tool conformance after SDK synchronization. | No change in tool IDs, streamed event ordering or provider options without documented migration. |  |
| **SDKFORK-05** | R28,R42 | automation | `REUSED_VERIFIED_PASS` | Run dependency drift checker with upstream one commit ahead in fixture metadata. | Produces report/candidate only; never auto-merges or rewrites Hanlin app code. |  |
| **CHAT-01** | R30,R31 | U/UI | `REUSED_VERIFIED_PASS` | Render a persisted user text message through the current chat surface. | Text, role, timestamp/model metadata and grouping match the current behavior; no new message model becomes source of truth. |  |
| **CHAT-02** | R30,R31 | U/UI | `REUSED_VERIFIED_PASS` | Render an assistant message with text + reasoning + tool activity + evidence + `NativeUIBlock`. | Every semantic section remains independently visible in the current renderer. |  |
| **CHAT-03** | R30 | UI | `REUSED_VERIFIED_PASS` | Render a plain assistant message over 20,000 characters. | Smooth scrolling; no message loss, duplicate text or new truncation. |  |
| **CHAT-04** | R30,R31 | UI | `REUSED_VERIFIED_PASS` | Stream 50 KB in many small deltas through the current renderer. | UI remains responsive; final rendered text exactly equals source stream. |  |
| **CHAT-05** | R30,R31 | UI | `REUSED_VERIFIED_PASS` | Stream answer text while surfaced reasoning/summary data updates rapidly. | Existing reasoning and answer presentation behave as before; no ordering loss. |  |
| **CHAT-06** | R30 | UI | `REUSED_VERIFIED_PASS` | Render Markdown headings, lists, blockquote, table, links, inline code and fenced blocks. | Existing rendering/selection/copy behavior is unchanged. |  |
| **CHAT-07** | R30,R35 | UI | `REUSED_VERIFIED_PASS` | Render fenced Python, JS, TypeScript, JSON, shell and Swift samples. | Current code content/labels/selection behavior remains unchanged; no renderer replacement occurs. |  |
| **CHAT-08** | R30 | UI | `REUSED_VERIFIED_PASS` | Render the existing LaTeX fixture. | Mathematical content renders equivalently to baseline. |  |
| **CHAT-09** | R30 | UI | `REUSED_VERIFIED_PASS` | Render resources/citations and open evidence sheet. | Existing resource/evidence navigation works unchanged. |  |
| **CHAT-10** | R30 | UI | `REUSED_VERIFIED_PASS` | Render map + route tool result. | Existing map/route UI remains interactive and unchanged. |  |
| **CHAT-11** | R30 | UI | `REUSED_VERIFIED_PASS` | Render calendar/event result. | Existing event card/section survives unchanged. |  |
| **CHAT-12** | R30 | UI | `REUSED_VERIFIED_PASS` | Render health/nutrition result. | Existing health card survives and is not flattened to text. |  |
| **CHAT-13** | R30 | UI | `REUSED_VERIFIED_PASS` | Render canvas result and use its open/edit action. | Current canvas surface/actions work unchanged. |  |
| **CHAT-14** | R30 | UI | `REUSED_VERIFIED_PASS` | Render HTML/web result. | Existing web preview/open behavior works unchanged. |  |
| **CHAT-15** | R30 | UI | `REUSED_VERIFIED_PASS` | Render code-execution result and use copy action. | Exact code/output is copied and remains attached to the correct message. |  |
| **CHAT-16** | R30 | UI | `REUSED_VERIFIED_PASS` | Render each existing `NativeUIBlock` fixture and an unknown/future block fallback. | Known blocks render; unknown handling remains explicit rather than silently disappearing. |  |
| **CHAT-17** | R30 | UI | `REUSED_VERIFIED_PASS` | Trigger a MiniApp launch action from a chat result. | Existing sheet/full-screen launch behavior and state remain unchanged. |  |
| **CHAT-18** | R30 | UI | `REUSED_VERIFIED_PASS` | Open AgentActivity inspector/evidence from an assistant turn. | Activity ordering, selected item and evidence remain correct. |  |
| **CHAT-19** | R30 | UI | `REUSED_VERIFIED_PASS` | Retry an assistant request through the existing retry action. | Existing retry pipeline is called exactly once; grouping stays correct. |  |
| **CHAT-20** | R30 | UI | `REUSED_VERIFIED_PASS` | Delete a message through current confirmation flow. | Only the selected message and its owned presentation disappear; persistence remains consistent. |  |
| **CHAT-21** | R30 | UI | `REUSED_VERIFIED_PASS` | Exercise TTS, copy, translate and share on assistant content. | All current actions work with identical semantics. |  |
| **CHAT-22** | R30,R32 | UI/D | `NOT_RUN_DEVICE` | Attach photo, PDF and arbitrary document using the current composer. | Existing preview and request/file pipeline receive the same URLs/data. |  |
| **CHAT-23** | R30,R32 | UI/D | `NOT_RUN_DEVICE` | Dictate text through the current voice/dictation path. | Apple/system permission flow and transcript insertion work as before. |  |
| **CHAT-24** | R30,R31,R32 | UI | `REUSED_VERIFIED_PASS` | Stop generation while a model/tool run is active. | Cancels the correct Hanlin run; current composer returns to idle; no stale output appends. |  |
| **CHAT-25** | R30 | UI | `REUSED_VERIFIED_PASS` | Test iPad portrait, landscape, split view and narrow window. | No new clipping/regression; current layout semantics remain intact. |  |
| **CHAT-26** | R30 | UI | `REUSED_VERIFIED_PASS` | Hebrew RTL conversation mixed with English and code. | Current alignment/direction/control behavior remains correct. |  |
| **CHAT-27** | R30 | UI/accessibility | `REUSED_VERIFIED_PASS` | Largest Dynamic Type + VoiceOver labels. | Current composer, message actions, tool states and rich-result actions remain usable. |  |
| **CHAT-28** | R30,R47 | B/source | `REUSED_VERIFIED_PASS` | Compare SwiftPM/project dependencies before/after. | No third-party chat UI package was added; current chat dependencies remain unless an unrelated accepted update requires a tested version change. |  |
| **CHAT-29** | R30,R47 | B/source | `REUSED_VERIFIED_PASS` | Diff `ChatView.swift`, `ChatViewComponents.swift`, `ChatViewBottom.swift` and related chat files. | No structural UI migration/decomposition. Every change is minimal and tied to a documented compatibility need. |  |
| **CHAT-30** | R30,R47 | B/source | `REUSED_VERIFIED_PASS` | Search for newly introduced chat-framework adapter/projection/message-model types. | None exist solely for a future UI migration. |  |
| **CHAT-31** | R30 | UI | `REUSED_VERIFIED_PASS` | Scroll mid-transcript while current assistant message receives streaming deltas. | User scroll position/auto-scroll behavior matches baseline. |  |
| **CHAT-32** | R30 | UI | `REUSED_VERIFIED_PASS` | Prepend older messages while user is mid-scroll. | Current pagination preserves stable message order/identity and expected position. |  |
| **CHAT-33** | R32 | UI | `REUSED_VERIFIED_PASS` | Change the selected model with the current model selector. | Existing model state/provider choice changes exactly as baseline. |  |
| **CHAT-34** | R32 | UI | `REUSED_VERIFIED_PASS` | Open current model-management surface and return. | No loss of draft text, attachments or selected mode state. |  |
| **CHAT-35** | R32 | UI | `REUSED_VERIFIED_PASS` | Type an `@model` query and select a suggestion. | Existing suggestion filtering/replacement behavior is unchanged. |  |
| **CHAT-36** | R32 | UI | `REUSED_VERIFIED_PASS` | Add/remove/edit prompt chips. | Existing prompt selection and request augmentation remain exact. |  |
| **CHAT-37** | R32 | UI | `REUSED_VERIFIED_PASS` | Add/remove selected URL previews. | Existing URL preview/request behavior remains exact. |  |
| **CHAT-38** | R32 | UI | `REUSED_VERIFIED_PASS` | Toggle tool-use mode. | Existing canonical-tool enablement/request state changes once and UI reflects it. |  |
| **CHAT-39** | R32 | UI | `REUSED_VERIFIED_PASS` | Select/change MCP chat server from the current composer. | Existing MCP selection state and request routing remain exact. |  |
| **CHAT-40** | R32 | UI | `REUSED_VERIFIED_PASS` | Toggle knowledge mode including unavailable-state alert. | Existing availability logic/alert and request state remain exact. |  |
| **CHAT-41** | R32 | UI | `REUSED_VERIFIED_PASS` | Toggle web-search mode including unavailable-state alert. | Existing availability logic/alert and request state remain exact. |  |
| **CHAT-42** | R32 | UI | `REUSED_VERIFIED_PASS` | Toggle reasoning/thinking and effort controls across supported/unsupported models. | Current visibility, state and provider options remain exact. |  |
| **CHAT-43** | R32 | UI | `REUSED_VERIFIED_PASS` | Exercise image-generation reverse prompt plus every current aspect/size choice. | Existing request payload semantics remain unchanged. |  |
| **CHAT-44** | R32 | UI | `REUSED_VERIFIED_PASS` | Exercise audio/voice generation controls. | Current mode remains reachable and maps to the same request state. |  |
| **CHAT-45** | R32 | UI | `REUSED_VERIFIED_PASS` | Exercise local-model-specific composer controls. | Existing local-model settings/actions remain reachable and unchanged. |  |
| **CHAT-46** | R32 | UI | `REUSED_VERIFIED_PASS` | Open current canvas shortcut and scroll-to-bottom control. | Both current actions remain available and behave as baseline. |  |
| **CHAT-47** | R32 | UI | `REUSED_VERIFIED_PASS` | Use current observe-send action. | Existing observe request path is called exactly once with correct state. |  |
| **CHAT-48** | R32 | UI/D | `NOT_RUN_DEVICE` | Paste a supported file/image into `InputTextField`. | Existing paste detection, file creation/selection and preview behavior remains unchanged. |  |
| **CHAT-49** | R30,R32 | UI | `REUSED_VERIFIED_PASS` | Focus/dismiss keyboard using touch, return/send and hardware keyboard. | Existing focus, submit and dismissal behavior remains unchanged. |  |
| **CHAT-50** | R30,R31,R32 | UI/I | `REUSED_VERIFIED_PASS` | Cancel a long run and immediately send a second request. | Old run cannot mutate the new turn; current UI leaves no stuck spinner. |  |
| **CHAT-51** | R30,R31 | UI/I | `REUSED_VERIFIED_PASS` | Run two separate conversations sequentially with different tools/models. | No UI state/tool activity leaks between conversations. |  |
| **CHAT-52** | R30,R31 | UI/persistence | `REUSED_VERIFIED_PASS` | Relaunch with an existing saved mixed conversation fixture. | Existing conversation renders with no migration/data loss and all rich results/actions intact. |  |
| **CHAT-53** | R30 | UI | `REUSED_VERIFIED_PASS` | Render consecutive user/assistant groups with split markers and model metadata. | Current grouping/separators/metadata display remain identical to baseline. |  |
| **CHAT-54** | R30,R31 | UI | `REUSED_VERIFIED_PASS` | Background/foreground the app during a supported streaming run and after completion. | Current state recovery behavior is preserved; no duplicated deltas or stale progress UI. |  |
| **CHAT-55** | R30,R31,R32,R47 | B/source/UI | `REUSED_VERIFIED_PASS` | Final frozen-UI audit: dependency graph, chat-file diff and full CHAT-01..54 suite. | No chat UI migration occurred; current Hanlin chat interface remains the product UI and all regressions are green or explicitly reported. |  |
| **YAML-01** | R33 | unit | `REUSED_VERIFIED_PASS` | Parse frontmatter with `name`, quoted description containing `:`, Unicode and CRLF. | Values are exact; body begins after closing delimiter. |  |
| **YAML-02** | R33 | unit | `REUSED_VERIFIED_PASS` | Parse folded `>` description across lines. | Standard YAML folded value is returned. |  |
| **YAML-03** | R33 | unit | `REUSED_VERIFIED_PASS` | Parse literal ` | ` multiline field. |  |
| **YAML-04** | R33 | unit | `REUSED_VERIFIED_PASS` | Parse frontmatter with unknown nested key/list. | Known metadata parses; unknown data can survive round-trip where store contract requires forward compatibility. |  |
| **YAML-05** | R33 | unit | `REUSED_VERIFIED_PASS` | Body contains a later line equal to `---`. | Only frontmatter boundary is treated as metadata delimiter; body is preserved. |  |
| **YAML-06** | R33 | unit | `REUSED_VERIFIED_PASS` | UTF-8 BOM + Hebrew Skill name/description. | Valid content imports without mangling. |  |
| **YAML-07** | R33 | unit | `REUSED_VERIFIED_PASS` | Malformed YAML. | Clear frontmatter parse error with location/context; no silent empty metadata fallback. |  |
| **YAML-08** | R33 | regression | `REUSED_VERIFIED_PASS` | Import every built-in/exported Skill fixture from old parser suite. | Existing valid Skills remain valid or have a documented standards-correct migration. |  |
| **YAML-09** | R33 | roundtrip | `REUSED_VERIFIED_PASS` | Import -> edit description -> export -> reimport. | `preferredToolIDs`, trigger hints, keywords and unknown supported metadata remain intact. |  |
| **DEP-01** | R39 | package | `REUSED_VERIFIED_PASS` | Resolve ZIPFoundation chosen current compatible version. | Build/test passes; Skill/file Office extraction fixtures unchanged. |  |
| **DEP-02** | R39 | package | `REUSED_VERIFIED_PASS` | Update SWCompression patch version. | MCP TGZ preview/extraction fixtures pass byte-for-byte semantic assertions. |  |
| **DEP-03** | R39 | package | `REUSED_VERIFIED_PASS` | Update SwiftSoup to chosen current stable. | WebRead extraction fixtures return same required title/body markers. |  |
| **DEP-04** | R39 | package | `REUSED_VERIFIED_PASS` | Update swift-log to current stable compatible API. | MCP/runtime logs compile and emit expected structured fields. |  |
| **DEP-05** | R39 | migration | `REUSED_VERIFIED_PASS` | Evaluate LaTeXSwiftUI 2.x in isolated commit. | Existing math fixtures render; otherwise revert and document blocker rather than forcing migration. |  |
| **DEP-06** | R39,R40 | migration | `REUSED_VERIFIED_PASS` | Evaluate LLM.swift 3.x in isolated commit with current local model fixture. | Model loads, streams, cancels and releases memory; otherwise keep existing version and document. |  |
| **DEP-07** | R36 | runtime | `REUSED_VERIFIED_PASS` | Build Python Apple support b11 through existing runtime bundle pipeline. | Device + simulator slices link; Python version/provenance reflect chosen release. |  |
| **DEP-08** | R36 | runtime | `REUSED_VERIFIED_PASS` | Build ios_system v3.0.7 through existing runtime pipeline. | Commands reported by backend match linked frameworks and acceptance suite. |  |
| **DEP-09** | R36 | runtime | `REUSED_VERIFIED_PASS` | Rebase QuickJS-NG v0.17.0 and minimal Hanlin allocator patch. | QuickJS conformance, typed OOM/stack/cancel tests all pass. |  |
| **DEP-10** | R36 | runtime | `REUSED_VERIFIED_PASS` | Validate current Node 24.5.0 mobile fork after all changes. | No downgrade; generic Node, npm and MCP server tests pass. |  |
| **DEP-11** | R37 | package | `REUSED_VERIFIED_PASS` | Query official NativeScript `ios-spm` refs/releases. | Upgrade occurs only if a matching complete runtime/core closure exists; otherwise exact 9.1.0 remains with evidence. |  |
| **DEP-12** | R38 | package/build | `REUSED_VERIFIED_PASS` | Query Expo official stable channel. If SDK 58 is still beta, align to latest SDK 57 stable patch; if 58 is stable by execution time, align to stable 58. | No `preview`, `beta`, `rc` or hand-mixed RN/Expo closure remains; official compatibility tooling determines versions. |  |
| **DEP-13** | R38 | build/UI | `REUSED_VERIFIED_PASS` | With SDK 57 on Xcode 27, enable/document official scene lifecycle support; with stable SDK 58, use its default supported scene path. Launch existing Expo brownfield probe. | App launches on iOS 27, window/scene lifecycle works, probe renders/interacts and background/foreground does not lose root view. |  |
| **DEP-14** | R42 | automation | `REUSED_VERIFIED_PASS` | Dependency report with safe patch, major update and unchanged packages. | Classifies each correctly; no automatic merge. |  |
| **DEP-15** | R42 | audit | `REUSED_VERIFIED_PASS` | Generate SBOM/dependency inventory with direct/transitive versions and licenses. | Every production third-party dependency is listed with source and chosen pin rule. |  |
| **PLATFORM-01** | MASTER-5 | build | `REUSED_VERIFIED_PASS` | Select stable Xcode 27, print `xcodebuild -version`, SDKs and `swift --version`. | Stable Xcode 27 is used; beta Xcode is not selected. |  |
| **PLATFORM-02** | MASTER-5 | source/build | `REUSED_VERIFIED_PASS` | Set app deployment target to iOS 27.0. | App compiles for iOS 27 simulator and generic device. |  |
| **PLATFORM-03** | MASTER-5 | package | `REUSED_VERIFIED_PASS` | Update product package iOS platform declarations to v27 where appropriate. | SwiftPM resolution/build succeeds under Xcode 27. |  |
| **PLATFORM-04** | MASTER-5 | host-tests | `REUSED_VERIFIED_PASS` | Evaluate macOS package target changes. | Host tests remain runnable on actual CI host; no needless macOS 27 target blocks execution. |  |
| **PLATFORM-05** | MASTER-5 | build | `REUSED_VERIFIED_PASS` | Build with Swift 6 strict concurrency diagnostics for modified modules. | No newly introduced unsafely ignored concurrency errors. |  |
| **PLATFORM-06** | MASTER-5 | simulator | `REUSED_VERIFIED_PASS` | Launch app on iPadOS 27 simulator. | Cold launch succeeds to main UI; no runtime framework load failure. |  |
| **PLATFORM-07** | MASTER-5 | device | `NOT_RUN_DEVICE` | Install signed build on iPadOS 27 device when available. | App launches and core runtime acceptance can execute. |  |
| **PLATFORM-08** | MASTER-5 | CI | `REUSED_VERIFIED_PASS` | Migrate workflow Xcode-selection logic from Xcode 26 to stable Xcode 27. | Targeted and full manual validation choose correct toolchain; existing inputs preserved. |  |
| **APPLEAI-01** | R45 | build | `NOT_RUN` | Compile the Foundation Models adapter with stable Xcode 27/iOS 27 SDK. | Uses public stable APIs accepted by the installed SDK; no beta/private import. |  |
| **APPLEAI-02** | R45 | unit | `REUSED_VERIFIED_PASS` | Inject unavailable-capability fixture/model state. | Provider reports unavailable with a typed/localized reason; no crash and no fallback to remote without explicit routing. |  |
| **APPLEAI-03** | R45 | unit/integration | `REUSED_VERIFIED_PASS` | Feed text stream fixture through adapter into Hanlin presentation. | Deltas preserve order, cancellation ID and final content; same conversation model is used. |  |
| **APPLEAI-04** | R45 | device | `NOT_RUN_DEVICE` | On Apple-Intelligence-capable iOS 27 device, send a deterministic short prompt to `SystemLanguageModel`. | Real on-device response streams; provider identity/latency recorded; no remote API key required. |  |
| **APPLEAI-05** | R45 | device | `NOT_RUN_DEVICE` | Send text + supported image multimodal prompt. | Image is accepted only when model capability says supported; response arrives through same Hanlin message path. |  |
| **APPLEAI-06** | R45 | device | `NOT_RUN_DEVICE` | Start long Apple model generation and cancel. | Generation stops/settles according to API; UI resets; new request starts without cross-run deltas. |  |
| **APPLEAI-07** | R45 | architecture/source | `REUSED_VERIFIED_PASS` | Inspect any Foundation Models `Tool` integration. | No independent tool business logic/executor duplicates Hanlin canonical tools. Tool requests, if supported, bridge to canonical authority or feature remains text-only with explicit limitation. |  |
| **APPLEAI-08** | R45 | regression | `REUSED_VERIFIED_PASS` | OS/model version prompt fixture pack across supported devices/OS images available in CI/device lab. | Semantic expectations/tolerance recorded because Apple system model may change with OS; exact-text assertions are used only when deterministic. |  |
| **COREAI-01** | R46 | package | `BLOCKED_DEPENDENCY` | Resolve official `apple/coreai-models`/Core AI integration at a stable compatible revision/tag. | License/source/pin recorded; no unofficial wrapper substituted. |  |
| **COREAI-02** | R46 | build | `BLOCKED_DEPENDENCY` | Compile Core AI provider/runtime for iOS 27. | Public Core AI/Foundation Models APIs compile under stable Xcode 27. |  |
| **COREAI-03** | R46 | device/input | `BLOCKED_INPUT_MODEL_FIXTURE` | Load a small supported `.aimodel` fixture, specialize and create `CoreAILanguageModel`. | Model reaches ready state; load/specialization latency and cache reuse recorded. If no redistributable fixture is supplied, disposition is `BLOCKED_INPUT_MODEL_FIXTURE`, not PASS. |  |
| **COREAI-04** | R46 | device | `NOT_RUN_DEVICE` | Stream a deterministic prompt through Core AI model in a Foundation Models session. | Output appears through Hanlin local-provider path; provider/runtime identity remains Core AI. |  |
| **COREAI-05** | R46 | device/perf | `NOT_RUN_DEVICE` | Measure cold load, warm load, first token, tokens/sec and peak memory. | Metrics saved and compared to configured regression thresholds; no unexplained runaway memory. |  |
| **COREAI-06** | R46 | regression | `BLOCKED_INPUT_MODEL_FIXTURE` | Run existing GGUF/LLM.swift local provider after Core AI is enabled. | GGUF path still loads/streams/cancels; Core AI did not replace or corrupt it. |  |
| **MCPSDK-01** | R29 | unit | `REUSED_VERIFIED_PASS` | Connect official MCP `Client` to deterministic in-process/mock transport. | Initialization/list tools uses SDK messages; no Hanlin duplicate protocol parser. |  |
| **MCPSDK-02** | R29 | integration | `REUSED_VERIFIED_PASS` | Start embedded Node `server-everything` fixture. | Official SDK client connects via `EmbeddedNodeMCPTransport` and discovers expected tools. |  |
| **MCPSDK-03** | R29 | integration | `REUSED_VERIFIED_PASS` | Invoke one MCP tool through canonical agent bridge. | Exactly one MCP SDK call; output maps to canonical tool result and presentation. |  |
| **MCPSDK-04** | R29 | integration | `REUSED_VERIFIED_PASS` | Server emits tool-list-changed notification. | Hanlin refreshes tool catalog without restart. |  |
| **MCPSDK-05** | R29 | integration | `REUSED_VERIFIED_PASS` | Kill/restart worker while one server selected. | Runtime state recovers; stale session/tool count is cleared and repopulated. |  |
| **MCPSDK-06** | R29 | persistence | `REUSED_VERIFIED_PASS` | Relaunch with two installed MCP servers and one selected per chat. | Registry/selection restore correctly; unselected server tools do not leak into request. |  |
| **MCPSDK-07** | R29 | source | `REUSED_VERIFIED_PASS` | Search for duplicate JSON-RPC/MCP message models outside official SDK adapters. | Any remaining duplicates have explicit Hanlin-specific reason or are removed. |  |
| **MCPSDK-08** | R29 | regression | `REUSED_VERIFIED_PASS` | Run current MCP path-migration fixtures. | Simplification does not reintroduce old absolute path migration bug. |  |
| **SCRIPTARCH-01** | R41 | architecture | `REUSED_VERIFIED_PASS` | Build call graph for ScriptUI -> host service request -> concrete adapter. | Every hop has a reason; redundant policy-only hop is identified for removal. |  |
| **SCRIPTARCH-02** | R41 | integration | `REUSED_VERIFIED_PASS` | JSC scripting fixture reads/writes package storage. | Works through simplified service path; relaunch preserves data. |  |
| **SCRIPTARCH-03** | R41 | integration | `REUSED_VERIFIED_PASS` | QuickJS fixture calls asynchronous host service. | Promise/result/cancellation semantics remain correct. |  |
| **SCRIPTARCH-04** | R41 | integration | `NOT_RUN` | Node scripting fixture calls permitted host file/network service. | Uses Node engine and receives real result; no fallback to QuickJS/JSC. | Remapped from package-routing test to real Node host services execution in fs01; pending test run. |
| **SCRIPTARCH-05** | R41 | integration | `NOT_RUN` | Python scripting fixture calls available host bridge. | Uses Python engine and preserves value conversion/errors. | Remapped from catalog retention test to real Python host bridge execution in fs01; pending test run. |
| **SCRIPTARCH-06** | R41 | UI | `REUSED_VERIFIED_PASS` | Render canonical ScriptUI fixture tree and interact with button/text/state/navigation. | UI tree and events remain correct after broker simplification. |  |
| **SCRIPTARCH-07** | R41 | agent | `REUSED_VERIFIED_PASS` | Installed Script package publishes tool; agent discovers and invokes it. | Tool result returns to Swift AI SDK and rich presentation survives. |  |
| **SCRIPTARCH-08** | R41 | lifecycle | `REUSED_VERIFIED_PASS` | Update script package, relaunch, then rollback. | Active generation changes atomically and rollback restores previous generation. |  |
| **SCRIPTARCH-09** | R41 | source | `REUSED_VERIFIED_PASS` | Remove trust/grant/policy layers designated obsolete. | No production caller still depends on removed state; no replacement security layer added. |  |
| **SCRIPTARCH-10** | R41 | regression | `REUSED_VERIFIED_PASS` | Existing extension/AppIntent/Widget snapshot tests. | Extension-safe paths remain functional; Node/Python are not accidentally linked into extension targets. |  |
| **DB-01** | R34 | baseline | `REUSED_VERIFIED_PASS` | Run current SQLite open/create/insert/select/update/delete fixture through `HanlinSQLiteService`. | Baseline outputs recorded before migration. |  |
| **DB-02** | R34 | baseline | `REUSED_VERIFIED_PASS` | Positional parameters, named parameters, NULL/bool/int/double/text/blob. | Values round-trip exactly under current bridge. |  |
| **DB-03** | R34 | baseline | `REUSED_VERIFIED_PASS` | Transaction commit and rollback fixture. | Atomic semantics recorded. |  |
| **DB-04** | R34 | prototype | `REUSED_VERIFIED_PASS` | If GRDB prototype is built, rerun DB-01..03 through same public Hanlin API. | Results match; no third-party DB model leaks into scripting protocol. |  |
| **DB-05** | R34 | prototype | `REUSED_VERIFIED_PASS` | Execute arbitrary valid SQL statement supported today. | GRDB path does not artificially narrow SQL surface. |  |
| **DB-06** | R34 | performance | `REUSED_VERIFIED_PASS` | Compare representative 1k inserts + 1k-row fetch and code complexity. | Adopt only with acceptable performance and meaningful maintenance reduction. |  |
| **DB-07** | R34 | decision | `REUSED_VERIFIED_PASS` | Produce `grdb-evaluation.md`. | Explicit ADOPT/KEEP decision with LOC/test/dependency evidence; no half-migrated dual DB layer. |  |
| **APPENG-01** | R37 | UI/device/sim | `NOT_RUN_DEVICE` | Launch NativeScript direct UIKit fixture using Metadata Bridge. | Native UIKit controller presents through Hanlin. |  |
| **APPENG-02** | R37 | UI/device/sim | `NOT_RUN_DEVICE` | Launch NativeScript fixture importing `@nativescript/core`. | Core module loads with runtime-matched version and renders. |  |
| **APPENG-03** | R37 | integration | `NOT_RUN` | NativeScript app calls Hanlin host service and returns result. | Bridge remains functional after policy simplification. | Remapped from package catalog test to real bridge E2E test; pending test run. |
| **APPENG-04** | R37 | agent | `NOT_RUN` | NativeScript/MiniApp tool is published and invoked by agent. | Canonical tool path works; rich result can open app UI. | Remapped from session cleanup test to canonical MiniApp tool execution test; pending test run. |
| **APPENG-05** | R38 | UI | `NOT_RUN` | Launch Expo production fixture after stable SDK 58 migration. | Brownfield root renders, events cross bridge, no missing Hermes/Expo symbols. | Remapped from AI_HLYTests unit test to actual HanlinExpoProductionE2ETests UI test; pending test run. |
| **APPENG-06** | R38 | concurrency | `REUSED_VERIFIED_PASS` | Open/close/reopen Expo app multiple times. | No duplicate runtime/session leak or stale root view. |  |
| **APPENG-07** | MASTER-1 | UI | `REUSED_VERIFIED_PASS` | Apps Hub lists Swift MiniApp, ScriptUI app, NativeScript app and Expo app together. | Each identity/runtime type is correct and launchable. |  |
| **APPENG-08** | MASTER-1 | regression | `REUSED_VERIFIED_PASS` | Sefaria, Wikipedia and Text Studio built-in MiniApps. | Launch, core data action and agent tool path pass. |  |
| **APPENG-09** | MASTER-1 | multiwindow | `REUSED_VERIFIED_PASS` | Launch supported MiniApp in sheet/window modes used by Hanlin. | Correct presentation and dismissal; chat state survives. |  |
| **ARCH-01** | MASTER-6 | docs | `REUSED_VERIFIED_PASS` | Read updated `AGENTS.md`/`PROJECT_AGENT_GUIDANCE.md`. | They no longer require downstream duplication for hypothetical upstream merges. |  |
| **ARCH-02** | MASTER-6 | docs | `REUSED_VERIFIED_PASS` | Search instructions for contradictory “never edit upstream files” rules. | Conflicts removed or explicitly scoped to third-party vendored code. |  |
| **ARCH-03** | R43 | source | `REUSED_VERIFIED_PASS` | Generate before/after LOC by subsystem. | Report shows where complexity was reduced; generated/vendor resources excluded from misleading LOC totals. |  |
| **ARCH-04** | R43 | source/build | `REUSED_VERIFIED_PASS` | Identify deleted legacy symbols and search all callers. | No production/test caller to deleted path remains. |  |
| **ARCH-05** | R43 | package | `REUSED_VERIFIED_PASS` | Run SwiftPM/Xcode dependency graph after cleanup. | Unused direct dependencies removed; needed transitive packages resolve once. |  |
| **ARCH-06** | R43 | binary | `REUSED_VERIFIED_PASS` | Compare app/runtime bundle sizes before/after. | Delta documented; unexpected major growth investigated. |  |
| **ARCH-07** | R44 | docs | `REUSED_VERIFIED_PASS` | Follow documented Agent -> Skill -> tool -> runtime sequence against code. | Docs match actual symbols/call graph. |  |
| **ARCH-08** | R44 | docs | `REUSED_VERIFIED_PASS` | Follow documented chat render sequence. | Docs identify authoritative Hanlin semantic model and optional third-party shell boundary. |  |
| **ARCH-09** | R44 | docs | `REUSED_VERIFIED_PASS` | Follow documented MCP sequence. | One official MCP SDK stack shown; no obsolete duplicate protocol path documented. |  |
| **ARCH-10** | R42,R44 | docs/automation | `REUSED_VERIFIED_PASS` | Run dependency inventory generator twice on unchanged tree. | Deterministic output/no meaningless churn. |  |
| **FINAL-01** | all | package | `REUSED_VERIFIED_PASS` | `swift test --package-path Packages/HanlinPlatform` under selected Xcode 27 toolchain. | All relevant package tests pass. | Authentic Phase 1 swift test execution on HanlinPlatform passed cleanly. |
| **FINAL-02** | all | node | `REUSED_VERIFIED_PASS` | `npm test` and integration suites for RuntimeCore Node host. | All tests match new policy expectations; obsolete “must be blocked” assertions are replaced, not merely skipped. | Both runtime and unit integration TAP suites authentic and passed. |
| **FINAL-03** | all | build | `NOT_RUN` | Xcode build-for-testing for iPadOS 27 simulator. | Success with exact log/result bundle. | iPadOS 27 simulator build-for-testing pending explicit operator CI dispatch. |
| **FINAL-04** | all | simulator | `NOT_RUN` | App unit/integration tests including Skills, canonical tools, runtime packages, HostServices and provider conformance. | PASS with xcresult evidence. | 235/260 cases proven clean; 25 affected tests require focused run before aggregate FINAL-04 can be certified. |
| **FINAL-05** | all | UI | `NOT_RUN` | Targeted UI tests for Skills, runtime command/install, ScriptUI, NativeScript, Expo, Agent conversation and rich chat. | PASS; screenshots/artifacts preserved for failures. | All 7 UI families accounted for; all 7 correctly classified as NOT_RUN pending authorized CI execution. |
| **FINAL-06** | all | CI | `NOT_RUN` | Manually dispatch affected-validation groups on saved commit. | All selected groups pass; run IDs recorded. | Pending authorized focused CI dispatch on saved commit. |
| **FINAL-07** | all | CI | `NOT_RUN` | Manually dispatch full validation once focused suites are green. | Full job passes on exact commit; no TestFlight/release publication. | Single-run full gate pending explicit operator authorization. |
| **FINAL-08** | all | device | `NOT_RUN_DEVICE` | Run `ON_DEVICE_ACCEPTANCE.md` updated for new architecture on signed iPadOS 27 build. | Device-specific engines and OS services pass or are individually `BLOCKED_EXTERNAL`/`FAIL`, never inferred from simulator. | Truthfully classified as NOT_RUN_DEVICE (no fake simulator substitution). |
| **FINAL-09** | all | provider | `NOT_RUN` | Run real-provider Skill/tool prompts including Code, package install, web and one rich native tool. | Model actually discovers/loads tools and uses them; no “isolated environment” hallucination without discovery attempt. | Dedicated semantic test implemented in MasterScenarioSemanticAcceptanceTests; pending test run. |
| **FINAL-10** | all | persistence | `NOT_RUN` | Cold terminate/relaunch after installed Skills, npm/Python packages, MCP server and Script app. | All intended state restores; no stale request-scoped exposed-tool state survives. | Dedicated semantic test implemented in MasterScenarioSemanticAcceptanceTests; pending test run. |
| **FINAL-11** | all | cancellation | `NOT_RUN` | Start long model/tool/runtime operation, cancel, immediately send small request. | Old run ceases visible effects; new run completes; no cross-run result contamination. | Dedicated semantic test implemented in MasterScenarioSemanticAcceptanceTests; pending test run. |
| **FINAL-12** | all | audit | `NOT_RUN` | Cross-join `capability-invariants.json`, `tool-inventory.json`, requirements and test IDs. | No invariant/tool/requirement lacks final disposition/evidence. | Machine-checkable cross-join test implemented in MasterScenarioSemanticAcceptanceTests; pending test run. |
