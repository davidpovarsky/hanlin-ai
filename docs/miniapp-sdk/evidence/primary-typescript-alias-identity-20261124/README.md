# Original TypeScript alias and compiler identity

The Expo package version **6.0.2** and executed compiler API version **6.0.3** describe two linked original packages. The existing SDK manifest explicitly records both identities. The retained source, lock, four actual SDK members and prior original-compiler audit agree; this clarification requires no production change or rerun.

## Actual resolution chain

`Scripts/Expo/package.json` declares `typescript: npm:@typescript/typescript6@6.0.2`. That original package has a 45-byte `lib/typescript.js` containing `module.exports = require("@typescript/old");`. Its dependency is `@typescript/old: npm:typescript@^6`, locked by the original Expo lock to `typescript@6.0.3`. The latter package contains the compiler implementation whose version literal and previously executed API report `6.0.3`.

## Exact actual SDK members

| Member under `MiniAppSDK/` | Bytes | SHA-256 |
|---|---:|---|
| `expo/node_modules/typescript/package.json` | 841 | `d9b8fb53c67c947fece83bcb73fa8512227ea6a12b110e096fdab8ecdc02b655` |
| `expo/node_modules/typescript/lib/typescript.js` | 45 | `d3f3cd2b04b7f466f4484df921b744223f7bd1f3e353ec9110bdf52695b983d5` |
| `expo/node_modules/@typescript/old/package.json` | 3,527 | `9332e97c30d3e53ed54910b89207ed657fb444066484df6e5b6965bf130865e9` |
| `expo/node_modules/@typescript/old/lib/typescript.js` | 9,144,216 | `569177652966bd528c319171c7dd22860dbf72bde116cbc4f644f1d02bb12e39` |

Every member matches its embedded manifest file record and the earlier original-compiler audit. The `d3f3…` SHA cited by focused proof is the wrapper entrypoint SHA; `569177…` is the compiler implementation SHA. Neither identity is replaced with a version label.

## Source and retained evidence

The source package and lock were read at `fd81d602d3b25f09162a659e1e0cf0582e91a93a`. Their SHA-256 values are `db6fd60dbc8f2b15eac5fee7029781cf14834ffbad53f0c8948fc4c2945c1e91` and `95d2a560d4eb01de64fcd0d43875a4ef2392e9747ed9fa79c2e0a0e58abececf`; both match the actual attempt6 manifest source inputs. The manifest SHA is `c9491455251124a82a7ca5721cc2fcd78e424670eeac53fdf8b1fc07abd4c325`. The existing installation metadata records the original `npm ci` inputs and content identity; it was reused without invoking npm.

The receipt retains complete lock entries, exact package identities, member hashes, selected prior audit evidence, source bindings and the previously verified archive identity. It cites the existing attempt6 reconciliation rather than copying or re-extracting the 81 MB archive.

## Verification boundary

This was an evidence-only read of existing immutable bytes. No compiler, test, generator, download, dependency modification or native command was executed. The next actual SDK must independently match these compiler member records and the source/lock before reusing this note. No future archive or application success is claimed.
