import { Intent, Script } from "scripting";
import { createSnapshotFromRequest, parseSnapshotRequest } from "./lib/mapSnapshot";

function readIntentInput(): unknown {
  const shortcut = Intent.shortcutParameter as any;
  if (shortcut?.value !== undefined && shortcut?.value !== null) {
    return shortcut.value;
  }

  if (Intent.textsParameter?.length) {
    return Intent.textsParameter[0];
  }

  if (Intent.urlsParameter?.length) {
    return Intent.urlsParameter[0];
  }

  return {};
}

async function run() {
  try {
    const request = parseSnapshotRequest(readIntentInput());
    const execution = await createSnapshotFromRequest(request, {
      defaultResponse: "file",
    });

    switch (execution.responseMode) {
      case "image":
        Script.exit(Intent.image(execution.image));
        break;
      case "base64":
        Script.exit(Intent.text(execution.result.base64 ?? execution.image.toPNGBase64String()));
        break;
      case "json":
        Script.exit(Intent.json(execution.result as any));
        break;
      case "file":
      default:
        Script.exit(Intent.file(execution.result.filePath));
        break;
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("Intent snapshot failed:", message);
    Script.exit(Intent.json({ ok: false, error: message } as any));
  }
}

run();
