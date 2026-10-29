import { init, jsInvoker } from "@hanlin/expo-native-api";
import { hostServices } from "@hanlin/expo-ui";

/**
 * Sefaria HTTPS via iOS Foundation NSURLSession through embedded NativeScript.
 * Avoids React Native RCTNetworking (crash) and embedded Node undici (fd errors).
 * NSURLSession callback is routed to the RN JS thread using jsInvoker.
 * Requires per-package ios-native-api and network consent.
 */
let nativeAPIReady = false;

function ensureNativeNetworking() {
  if (nativeAPIReady) return;
  let installed = false;
  try {
    installed = init("", { globals: true });
  } catch (error) {
    throw new Error("Native iOS API initialization failed: " +
      String(error?.message || error));
  }
  if (!installed) {
    throw new Error("NativeScript Native API is unavailable. Approve ios-native-api for this package.");
  }
  if (typeof NSURL === "undefined" ||
      typeof NSURLSession === "undefined" ||
      typeof NSMutableURLRequest === "undefined" ||
      typeof NSString === "undefined") {
    throw new Error("Foundation networking classes are unavailable in this Hanlin runtime.");
  }
  nativeAPIReady = true;
}

function checkedSefariaUrl(value) {
  const url = new URL(String(value));
  if (url.protocol !== "https:" || url.hostname !== "www.sefaria.org" ||
      url.port !== "" || url.username || url.password) {
    throw new Error("Only https://www.sefaria.org is permitted.");
  }
  if (!url.pathname.startsWith("/api/")) {
    throw new Error("Only Sefaria API paths may be requested.");
  }
  return url.toString();
}

export async function requestJson(url, options = {}) {
  const safeURL = checkedSefariaUrl(url);
  const method = String(options.method || "GET").toUpperCase();
  if (method !== "GET" && method !== "POST") {
    throw new Error("Unsupported Sefaria request method.");
  }
  const nativeAllowed = await hostServices.hasCapability("ios-native-api");
  const networkAllowed = await hostServices.hasCapability("network");
  if (!nativeAllowed || !networkAllowed) {
    throw new Error("Missing required permission: " + (!nativeAllowed ? "ios-native-api" : "network"));
  }
  ensureNativeNetworking();

  return new Promise((resolve, reject) => {
    let settled = false;
    let task = null;
    let timeout = null;
    function finish(error, value) {
      if (settled) return;
      settled = true;
      if (timeout !== null) clearTimeout(timeout);
      if (error) reject(error);
      else resolve(value);
    }
    try {
      const nsURL = NSURL.URLWithString(safeURL);
      if (!nsURL) throw new Error("Cannot create native Sefaria URL.");

      const request = NSMutableURLRequest.requestWithURL(nsURL);
      request.HTTPMethod = method;
      request.timeoutInterval = 24;
      request.setValueForHTTPHeaderField("application/json", "Accept");

      if (method === "POST") {
        const body = String(options.body || "");
        const nsBody = NSString.stringWithString(body);
        request.HTTPBody = nsBody.dataUsingEncoding(4);
        request.setValueForHTTPHeaderField("application/json", "Content-Type");
      }

      const completion = jsInvoker((data, response, error) => {
        try {
          if (error) {
            throw new Error("iOS URLSession: " +
              String(error.localizedDescription || error));
          }
          const status = Number(response?.statusCode || 0);
          if (!data) throw new Error("Sefaria returned an empty HTTP response.");
          const nsText = NSString.alloc().initWithDataEncoding(data, 4);
          if (!nsText) throw new Error("Unable to decode Sefaria response as UTF-8.");
          const raw = String(nsText);
          let json;
          try {
            json = raw ? JSON.parse(raw) : null;
          } catch {
            throw new Error("Sefaria returned non-JSON HTTP " + status + ".");
          }
          if (status < 200 || status >= 300) {
            const message = json?.error || json?.detail || json?.message || "HTTP error";
            throw new Error("Sefaria HTTP " + status + ": " + String(message));
          }
          finish(null, json);
        } catch (reason) {
          finish(reason instanceof Error ? reason : new Error(String(reason)));
        }
      });

      task = NSURLSession.sharedSession.dataTaskWithRequestCompletionHandler(request, completion);
      if (!task) throw new Error("iOS could not create a native URLSession data task.");
      timeout = setTimeout(() => {
        try { task?.cancel(); } catch {}
        finish(new Error("Sefaria native iOS request timed out after 28 seconds."));
      }, 28000);
      task.resume();
    } catch (error) {
      finish(error instanceof Error ? error : new Error(String(error)));
    }
  });
}
