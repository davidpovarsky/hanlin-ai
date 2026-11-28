# HANLIN — תחקור מדויק של ריצות Apple מקוריות, 19.11.2026

**בדיקת הלוגים:** 2026-11-19 14:15 UTC. כל ריצה מקושרת למקור ה־SHA שלה, ולא ניתן להסיק הצלחה ב־HEAD 114c98d4fc9228882f89efd74bfa011f3a4830e0 מריצה ישנה.

| Run | SHA | מצבו באמת | הגורם שזוהה / מה עוד לא ידוע | פעולה הבאה |
|---|---|---|---|---|
| [44466305765](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44466305765) | 6b5dc2c0 | FAIL לפני בדיקות DATA/Composer | Scripts/Runtime/prepare-runtime-core.sh: RuntimeDependencies.lock.json verified; **release not found** בהכנת embedded RuntimeCore | לתקן source/pin/release/artifact lookup ולאחר מכן להריץ את ה־unit selectors בדיוק |
| [44466312634](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44466312634) | 6b5dc2c0 | **6 test cases; 5 failures, 3 unexpected** | xcodebuild exit status **65**, ולא 65 בדיקות. Failure messages: 0 components במקום 5; invalid state transition idle to failed(deinit) | לחלץ case-level xcresult, לשחזר התנהגות, לתקן A2UI lifecycle/Surface ולרוץ שוב |
| [44466308930](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44466308930) | 6b5dc2c0 | FAIL paired product_and_share | ה־CI מדווח **Original native acceptance did not pass every case in the recorded scope**; לא ניתן לייחס ללא קריאת xcresult את כל מקרים לגרסת התיקון האחרונה | raw product/share case-level, לתקן return/cancel/share ולבדוק אינטגרציה מלאה |
| [44465711797](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44465711797) | 8e2f8924 | **XCUITest PASS**; workflow FAIL | testDRapidInputDiagnosticOnly עבר ב־135.070 שניות, **1 test, 0 failures**; כתיבת ארכיון תוצאות הסתיימה, ואז Python **AssertionError at line 18** ב־post-test gate | לתקן gate/trace assertion, לא לדווח על test failure מדומה; Motion B + 100 preset cycles עדיין לא מאושרים |
| [44458939610](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44458939610) | ffc876fd | TEST BUILD FAILED, 0 targeted compact UI cases | Swift test target failed to compile: SurfaceViewModel.components does not exist; require macro throws without try. ה־xcodebuild יצא 65; מופיע סיכום 26 compiler failures (לא 26 UI tests) | תיקון API/try ב־6b5dc2c0 קיים; להריץ compact selectors מחדש על current source |
| [44459110497](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44459110497) | 25c28ae8 | TEST BUILD FAILED, 0 target provider UI cases | אותן שגיאות compile של test target; אין ראיית auth/credentials native pass | להריץ exact provider/Keychain scenarios על קוד מתוקן; לא להעתיק secret |
| [44447126258](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44447126258) | 7e27ded6 | 14/14 unit PASS; **4/17 UI PASS, 13 UI FAIL** | native UI surfaces/Composer/consent/reasoning; מקור מוקדם | לשחזר מאפיינים על current source |
| [44447129341](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44447129341) | 7e27ded6 | 5/8 PASS, 3/8 UI FAIL | package transfer/reopen/rollback + 4 Host PASS, three UI cases failed before Send | תיקון first-character/caret + paired retest |
| [44453570922](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44453570922) | 873607e4 | SUCCESS | Skills/Yams/Python workflow passed | לקשור case-level exact proofs לששת צרכנים, original Skill Center |
| [44467193357](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44467193357) | f7082624 | SUCCESS main workflow | רק upstream PR16 merged; לא product acceptance | לא להתייחס כחתימה/שחרור |

## שינוי מהותי מול המסירה הישנה
- '65 A2UI failing unit tests' היה פירוש שגוי של status 65. הנכון: **6 executed, 5 failed (3 unexpected)**.
- 'Motion D XCUITest failed' היה ניסוח שגוי. הנכון: **XCUITest PASS, post-test Python assertion FAIL**.
- 'provider credentials run failed in the real login flow' לא הוכח: אותה ריצה נעצרה ב־build test target לפני הבדיקה.
- 'RuntimeCore test failed' לא הוכח: **RuntimeCore preparation** נכשל לפני test execution.
- 'paired 3/8 failed' הוכח בריצה היסטורית 44447129341; תוצאות case-level של 44466308930 עדיין דורשות raw original result.

## קובצי ראיות ומקומות
- מסירת מקור: docs/continuation-20261117/acceptance/HANLIN_NEW_CHAT_HANDOFF_20261119.md.
- מרשם קבלה: docs/continuation-20261117/acceptance/ACCEPTANCE_REGISTER.json (generated 04:46 UTC, older snapshot).
- raw artifact iPad historical: C:\Users\DAVID\Code\Hanlin-Continuation-Evidence-20261119\run-44447126258\root-verified-artifact.
- GitHub links בטבלה הם הוכחת run/job; xcresult המקורי נחוץ לשיוך מדויק של case-level.
- אין להעתיק secrets למאגר, אין לטעון signed IPA או iPad physical pass ללא ראיות.
