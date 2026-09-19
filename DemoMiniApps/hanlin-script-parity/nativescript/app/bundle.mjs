// HanlinScript Parity Mini App
// Proves deterministic Node, Python, JavaScript, and HTTPS execution,
// canonical private storage, and host-bound inter-app requests.

console.log("[HanlinScriptParity] Initializing bundle...");

const bridge = typeof HanlinNativeServicesBridge !== "undefined" ? HanlinNativeServicesBridge : null;

// Helpers to invoke bridge methods with support for various ObjC selector manglings
function runJS(code, cb) {
  if (!bridge) return cb(null, "Bridge unavailable");
  if (typeof bridge.executeJavaScript === "function") {
    bridge.executeJavaScript(code, cb);
  } else if (typeof bridge.executeJavaScriptCompletion === "function") {
    bridge.executeJavaScriptCompletion(code, cb);
  } else {
    cb(null, "executeJavaScript method not found");
  }
}

function runNode(code, cb) {
  if (!bridge) return cb(null, "Bridge unavailable");
  if (typeof bridge.executeNode === "function") {
    bridge.executeNode(code, cb);
  } else if (typeof bridge.executeNodeCompletion === "function") {
    bridge.executeNodeCompletion(code, cb);
  } else {
    cb(null, "executeNode method not found");
  }
}

function runPython(code, cb) {
  if (!bridge) return cb(null, "Bridge unavailable");
  if (typeof bridge.executePython === "function") {
    bridge.executePython(code, cb);
  } else if (typeof bridge.executePythonCompletion === "function") {
    bridge.executePythonCompletion(code, cb);
  } else {
    cb(null, "executePython method not found");
  }
}

function fetchHTTPS(url, cb) {
  if (!bridge) return cb(null, "Bridge unavailable");
  if (typeof bridge.fetchURL === "function") {
    bridge.fetchURL(url, cb);
  } else if (typeof bridge.fetchURLCompletion === "function") {
    bridge.fetchURLCompletion(url, cb);
  } else {
    cb(null, "fetchURL method not found");
  }
}

function sendInterApp(targetID, action, capability, payloadJSON, cb) {
  if (!bridge) return cb(null, "Bridge unavailable");
  if (typeof bridge.sendRequestActionCapabilityPayloadJSONCompletion === "function") {
    bridge.sendRequestActionCapabilityPayloadJSONCompletion(targetID, action, capability, payloadJSON, cb);
  } else if (typeof bridge.sendRequest === "function") {
    bridge.sendRequest(targetID, action, capability, payloadJSON, cb);
  } else {
    cb(null, "sendRequest method not found");
  }
}

// Storage helpers using NSProcessInfo environment / bridge
function getStateDirectory() {
  if (bridge && typeof bridge.stateDirectory === "function") {
    try {
      const dir = bridge.stateDirectory();
      if (dir) return dir.toString();
    } catch (e) {
      console.warn("[HanlinScriptParity] bridge.stateDirectory() call failed: " + e);
    }
  }
  const env = NSProcessInfo.processInfo.environment;
  const miniappStateDir = env.objectForKey("HANLIN_MINIAPP_STATE_DIR");
  if (miniappStateDir) return miniappStateDir.toString();
  const miniappDataRoot = env.objectForKey("HANLIN_MINIAPP_DATA_ROOT");
  if (miniappDataRoot) return miniappDataRoot.toString() + "/state";
  const stateDir = env.objectForKey("HANLIN_STATE_DIR");
  if (stateDir) return stateDir.toString();
  const dataRoot = env.objectForKey("HANLIN_DATA_ROOT");
  if (dataRoot) return dataRoot.toString() + "/state";
  return null;
}

let counter = 0;
let persistedName = "HanlinScript";

function saveStorage() {
  const dir = getStateDirectory();
  if (!dir) return "Error: No state directory found";
  try {
    const filePath = dir + "/script-parity.json";
    const content = JSON.stringify({ counter: counter, name: persistedName, timestamp: Date.now() });
    const nsStr = NSString.stringWithString(content);
    const success = nsStr.writeToFileAtomicallyEncodingError(filePath, true, 4, null); // 4 = NSUTF8StringEncoding
    return success ? "Saved in canonical private container" : "Write returned false";
  } catch (e) {
    return "Save error: " + e;
  }
}

function loadStorage() {
  const dir = getStateDirectory();
  if (!dir) return "Error: No state directory found";
  try {
    const filePath = dir + "/script-parity.json";
    const nsStr = NSString.stringWithContentsOfFileEncodingError(filePath, 4, null);
    if (!nsStr) return "No saved state yet";
    const parsed = JSON.parse(nsStr.toString());
    if (typeof parsed.counter === "number") counter = parsed.counter;
    if (typeof parsed.name === "string") persistedName = parsed.name;
    return "Reloaded persisted state (counter=" + counter + ")";
  } catch (e) {
    return "Load error: " + e;
  }
}

// Register inter-app request handler so Swift Parity and AppIntents can call us
if (bridge) {
  try {
    const registerFn = bridge.registerRequestHandlerCapabilityHandler || bridge.registerRequestHandler;
    if (typeof registerFn === "function") {
      const handleRequest = (actionName) => (caller, payloadJSON, reply) => {
        console.log("[HanlinScriptParity] Received " + actionName + " from " + caller + ": " + payloadJSON);
        const replyPayload = JSON.stringify({
          source: "hanlin.demo.script-parity",
          action: actionName,
          counter: counter,
          name: persistedName
        });
        reply(replyPayload, null);
      };
      registerFn.call(bridge, "share.value", "inter-app.share", handleRequest("share.value"));
      registerFn.call(bridge, "parity.intent", "inter-app.share", handleRequest("parity.intent"));
    }
  } catch (e) {
    console.error("[HanlinScriptParity] Error registering handler: " + e);
  }
}

// Build Direct UIKit UI
const rootVC = UIViewController.new();
rootVC.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

const scrollView = UIScrollView.alloc().initWithFrame(rootVC.view.bounds);
scrollView.autoresizingMask = 18; // UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight
rootVC.view.addSubview(scrollView);

let yOffset = 40;

function addHeader(title) {
  const label = UILabel.alloc().initWithFrame(CGRectMake(24, yOffset, 340, 32));
  label.text = title;
  label.font = UIFont.boldSystemFontOfSize(24);
  label.textColor = UIColor.labelColor;
  scrollView.addSubview(label);
  yOffset += 40;
  return label;
}

function addLabel(text, id, fontSize = 14) {
  const label = UILabel.alloc().initWithFrame(CGRectMake(24, yOffset, 340, 36));
  label.text = text;
  label.font = UIFont.systemFontOfSize(fontSize);
  label.textColor = UIColor.secondaryLabelColor;
  label.numberOfLines = 2;
  if (id) label.accessibilityIdentifier = id;
  scrollView.addSubview(label);
  yOffset += 40;
  return label;
}

function addButton(title, id, onClick) {
  const btn = UIButton.buttonWithType(1); // System
  btn.frame = CGRectMake(24, yOffset, 340, 44);
  btn.setTitleForState(title, 0);
  btn.backgroundColor = UIColor.systemEmeraldColor || UIColor.systemGreenColor;
  btn.setTitleColorForState(UIColor.whiteColor, 0);
  btn.layer.cornerRadius = 10;
  btn.clipsToBounds = true;
  if (id) btn.accessibilityIdentifier = id;
  // Use Target-Action via NativeScript block or simple click simulation
  scrollView.addSubview(btn);
  yOffset += 52;
  return btn;
}

// 1. Header
const titleLabel = addHeader("HanlinScript Parity");
titleLabel.accessibilityIdentifier = "hanlin-script-parity-title";

// 2. Storage Section
addLabel("Private Durable Storage", null, 17);
const counterLabel = addLabel("Counter: 0", "hanlin-script-parity-counter-label");
const storageStatusLabel = addLabel("Storage: Initializing...", "hanlin-script-parity-storage-status");

// 3. Runtimes Section
addLabel("Deterministic Runtimes", null, 17);
const jsStatusLabel = addLabel("JavaScript: Pending...", "hanlin-script-parity-lbl-js");
const nodeStatusLabel = addLabel("Node: Pending...", "hanlin-script-parity-lbl-node");
const pythonStatusLabel = addLabel("Python: Pending...", "hanlin-script-parity-lbl-python");
const networkStatusLabel = addLabel("HTTPS Fetch: Pending...", "hanlin-script-parity-lbl-network");
const interAppStatusLabel = addLabel("Inter-App Share: Pending...", "hanlin-script-parity-lbl-interapp");

scrollView.contentSize = CGSizeMake(340, yOffset + 60);

// Auto-run deterministic verification passes
loadStorage();
counterLabel.text = "Counter: " + counter;
storageStatusLabel.text = saveStorage();

runJS("6 * 7", (res, err) => {
  jsStatusLabel.text = "JS: " + (err ? "Err: " + err : res);
});

runNode("console.log(123 * 2);", (res, err) => {
  nodeStatusLabel.text = "Node: " + (err ? "Err: " + err : res);
});

runPython("print(100 + 23)", (res, err) => {
  pythonStatusLabel.text = "Python: " + (err ? "Err: " + err : res);
});

fetchHTTPS("https://en.wikipedia.org/", (res, err) => {
  networkStatusLabel.text = "HTTPS: " + (err ? "Err: " + err : res);
});

sendInterApp("hanlin.demo.swift-parity", "share.value", "inter-app.share", JSON.stringify({ requested: "swift-state" }), (res, err) => {
  interAppStatusLabel.text = "Inter-App: " + (err ? "Err: " + err : res);
});

// Present UI
try {
  if (typeof NativeScriptEmbedder !== "undefined" && NativeScriptEmbedder.sharedInstance) {
    const embedder = NativeScriptEmbedder.sharedInstance();
    if (embedder && embedder.delegate) {
      console.log("[HanlinScriptParity] Presenting root view controller...");
      embedder.delegate.presentNativeScriptApp(rootVC);
    }
  }
} catch (e) {
  console.error("[HanlinScriptParity] Presentation error: " + e);
}

console.log("[HanlinScriptParity] Bundle setup complete.");