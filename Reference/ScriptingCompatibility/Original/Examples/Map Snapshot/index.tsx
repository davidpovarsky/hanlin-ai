import { Navigation, Script } from "scripting";
import { createSnapshotFromRequest, hasAnyQueryParameters, requestedUI } from "./lib/mapSnapshot";
import { View } from "./page";

async function run() {
  const rawParameters = Script.queryParameters ?? {};
  const hasParameters = hasAnyQueryParameters(rawParameters);

  if (requestedUI(rawParameters, hasParameters)) {
    await Navigation.present({
      element: <View />,
      modalPresentationStyle: "overFullScreen",
    });
    Script.exit();
  }

  try {
    const execution = await createSnapshotFromRequest(rawParameters, {
      defaultResponse: "json",
    });
    Script.exit(execution.result as any);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("Headless map snapshot failed:", message);
    Script.exit({ ok: false, error: message } as any);
  }
}

run().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(message);
  Script.exit({ ok: false, error: message } as any);
});
