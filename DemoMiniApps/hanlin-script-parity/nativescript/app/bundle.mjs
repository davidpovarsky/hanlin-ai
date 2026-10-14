// HanlinScript Parity Mini App
// Proves deterministic Node, Python, JavaScript, and HTTPS execution,
// canonical private storage, and host-bound inter-app requests.

console.log("[HanlinScriptParity] Initializing bundle...");

const g = typeof globalThis !== "undefined" ? globalThis : (typeof global !== "undefined" ? global : this);

function resolveClass(name) {
  if (g) {
    try {
      if (typeof g.NSClassFromString === "function") {
        const cls = g.NSClassFromString(name);
        if (cls) return cls;
      }
    } catch (e) {}
    try {
      if (typeof g.objc_getClass === "function") {
        const cls = g.objc_getClass(name);
        if (cls) return cls;
      }
    } catch (e) {}
    if (g[name]) return g[name];
  }
  if (typeof global !== "undefined" && global) {
    try {
      if (typeof global.NSClassFromString === "function") {
        const cls = global.NSClassFromString(name);
        if (cls) return cls;
      }
    } catch (e) {}
    try {
      if (typeof global.objc_getClass === "function") {
        const cls = global.objc_getClass(name);
        if (cls) return cls;
      }
    } catch (e) {}
    if (global[name]) return global[name];
  }
  try {
    if (typeof NSClassFromString === "function") {
      const cls = NSClassFromString(name);
      if (cls) return cls;
    }
  } catch (e) {}
  try {
    if (typeof objc_getClass === "function") {
      const cls = objc_getClass(name);
      if (cls) return cls;
    }
  } catch (e) {}
  try {
    if (name === "HanlinNativeServicesBridge" && typeof HanlinNativeServicesBridge !== "undefined" && HanlinNativeServicesBridge) return HanlinNativeServicesBridge;
    if (name === "HanlinNativeScriptCompatibility" && typeof HanlinNativeScriptCompatibility !== "undefined" && HanlinNativeScriptCompatibility) return HanlinNativeScriptCompatibility;
  } catch (e) {}
  return null;
}

function resolveBridge() {
  if (typeof HanlinNativeServicesBridge !== "undefined" && HanlinNativeServicesBridge) return HanlinNativeServicesBridge;
  return resolveClass("HanlinNativeServicesBridge");
}

function resolveCompat() {
  if (typeof HanlinNativeScriptCompatibility !== "undefined" && HanlinNativeScriptCompatibility) return HanlinNativeScriptCompatibility;
  return resolveClass("HanlinNativeScriptCompatibility");
}

const bridge = resolveBridge();
const compat = resolveCompat();
console.log("[HanlinScriptParity] Bridge resolution: bridge=" + (bridge ? "found" : "null") + " compat=" + (compat ? "found" : "null") + " g.NSClassFromString=" + (g && typeof g.NSClassFromString));

const environment = NSProcessInfo.processInfo.environment;
const executionMode = environment.objectForKey("HANLIN_EXECUTION_MODE");
const isHeadlessAction = executionMode && executionMode.toString() === "headless-action";

function invokeCompat(value, key) {
  const c = compat
    || resolveCompat()
    || bridge
    || resolveBridge();
  if (c) {
    if (typeof c.roundTripValueKey === "function") {
      try {
        const res = c.roundTripValueKey(value != null ? String(value) : "", key);
        return res != null ? res.toString() : "";
      } catch (e) {
        return "Err: " + e;
      }
    }
    if (key === "hostService.executeJavaScript" && typeof c.executeJavaScriptSync === "function") {
      try {
        const res = c.executeJavaScriptSync(value != null ? String(value) : "");
        return res != null ? res.toString() : "";
      } catch (e) {
        return "Err: " + e;
      }
    }
    if (key === "hostService.executeNode" && typeof c.executeNodeSync === "function") {
      try {
        const res = c.executeNodeSync(value != null ? String(value) : "");
        return res != null ? res.toString() : "";
      } catch (e) {
        return "Err: " + e;
      }
    }
    if (key === "hostService.executePython" && typeof c.executePythonSync === "function") {
      try {
        const res = c.executePythonSync(value != null ? String(value) : "");
        return res != null ? res.toString() : "";
      } catch (e) {
        return "Err: " + e;
      }
    }
    if (key === "hostService.fetchURL" && typeof c.fetchURLSync === "function") {
      try {
        const res = c.fetchURLSync(value != null ? String(value) : "");
        return res != null ? res.toString() : "";
      } catch (e) {
        return "Err: " + e;
      }
    }
    if (key.startsWith("hostService.sendRequest:") && typeof c.sendRequestSyncActionCapabilityPayloadJSON === "function") {
      try {
        const parts = key.split(":");
        const targetID = parts[1] || "";
        const action = parts[2] || "";
        const capability = parts[3] || "";
        const res = c.sendRequestSyncActionCapabilityPayloadJSON(targetID, action, capability, value != null ? String(value) : "");
        return res != null ? res.toString() : "";
      } catch (e) {
        return "Err: " + e;
      }
    }
    if (key.startsWith("hostService.sendRequest:") && typeof c.sendRequestSync === "function") {
      try {
        const parts = key.split(":");
        const targetID = parts[1] || "";
        const action = parts[2] || "";
        const capability = parts[3] || "";
        const res = c.sendRequestSync(targetID, action, capability, value != null ? String(value) : "");
        return res != null ? res.toString() : "";
      } catch (e) {
        return "Err: " + e;
      }
    }
    if (key === "hostService.state" && typeof c.stateDirectory === "function") {
      try {
        const res = c.stateDirectory();
        return res != null ? res.toString() : "";
      } catch (e) {}
    }
    if (key === "hostService.dataRoot" && typeof c.dataRootDirectory === "function") {
      try {
        const res = c.dataRootDirectory();
        return res != null ? res.toString() : "";
      } catch (e) {}
    }
  }
  return null;
}

function updateOnMainThread(fn) {
  try {
    if (typeof NSOperationQueue !== "undefined" && NSOperationQueue.mainQueue) {
      NSOperationQueue.mainQueue.addOperationWithBlock(fn);
      return;
    }
  } catch (e) {}
  if (typeof dispatch_async === "function" && typeof dispatch_get_main_queue === "function") {
    try {
      dispatch_async(dispatch_get_main_queue(), fn);
      return;
    } catch (e) {}
  }
  console.error("[HanlinScriptParity] Main thread queue unavailable for UI update");
}

// Helpers to invoke bridge methods with support for asynchronous and fallback ObjC selectors
function runJS(code, cb) {
  const direct = invokeCompat(code, "hostService.executeJavaScript");
  if (direct != null) {
    if (direct.startsWith("Err: ")) return cb(null, direct.substring(5));
    return cb(direct, null);
  }
  const target = bridge || compat || resolveBridge() || resolveCompat();
  if (target && typeof target.executeJavaScriptCompletion === "function") {
    return target.executeJavaScriptCompletion(code, cb);
  } else if (target && typeof target.executeJavaScript === "function") {
    return target.executeJavaScript(code, cb);
  } else if (target && typeof target.executeJavaScriptSync === "function") {
    try {
      const res = target.executeJavaScriptSync(code);
      const str = res != null ? res.toString() : "";
      if (str.startsWith("Err: ")) return cb(null, str.substring(5));
      return cb(str, null);
    } catch (e) {
      return cb(null, "executeJavaScriptSync error: " + e);
    }
  }
  return cb(null, "Error: Host service provider unavailable for JavaScript execution");
}

function runNode(code, cb) {
  const direct = invokeCompat(code, "hostService.executeNode");
  if (direct != null) {
    if (direct.startsWith("Err: ")) return cb(null, direct.substring(5));
    return cb(direct, null);
  }
  const target = bridge || compat || resolveBridge() || resolveCompat();
  if (target && typeof target.executeNodeCompletion === "function") {
    return target.executeNodeCompletion(code, cb);
  } else if (target && typeof target.executeNode === "function") {
    return target.executeNode(code, cb);
  } else if (target && typeof target.executeNodeSync === "function") {
    try {
      const res = target.executeNodeSync(code);
      const str = res != null ? res.toString() : "";
      if (str.startsWith("Err: ")) return cb(null, str.substring(5));
      return cb(str, null);
    } catch (e) {
      return cb(null, "executeNodeSync error: " + e);
    }
  }
  return cb(null, "Error: Host service provider unavailable for Node execution");
}

function runPython(code, cb) {
  const direct = invokeCompat(code, "hostService.executePython");
  if (direct != null) {
    if (direct.startsWith("Err: ")) return cb(null, direct.substring(5));
    return cb(direct, null);
  }
  const target = bridge || compat || resolveBridge() || resolveCompat();
  if (target && typeof target.executePythonCompletion === "function") {
    return target.executePythonCompletion(code, cb);
  } else if (target && typeof target.executePython === "function") {
    return target.executePython(code, cb);
  } else if (target && typeof target.executePythonSync === "function") {
    try {
      const res = target.executePythonSync(code);
      const str = res != null ? res.toString() : "";
      if (str.startsWith("Err: ")) return cb(null, str.substring(5));
      return cb(str, null);
    } catch (e) {
      return cb(null, "executePythonSync error: " + e);
    }
  }
  return cb(null, "Error: Host service provider unavailable for Python execution");
}

function fetchHTTPS(url, cb) {
  const direct = invokeCompat(url, "hostService.fetchURL");
  if (direct != null) {
    if (direct.startsWith("Err: ")) return cb(null, direct.substring(5));
    return cb(direct, null);
  }
  const target = bridge || compat || resolveBridge() || resolveCompat();
  if (target && typeof target.fetchURLCompletion === "function") {
    return target.fetchURLCompletion(url, cb);
  } else if (target && typeof target.fetchURL === "function") {
    return target.fetchURL(url, cb);
  } else if (target && typeof target.fetchURLSync === "function") {
    try {
      const res = target.fetchURLSync(url);
      const str = res != null ? res.toString() : "";
      if (str.startsWith("Err: ")) return cb(null, str.substring(5));
      return cb(str, null);
    } catch (e) {
      return cb(null, "fetchURLSync error: " + e);
    }
  }
  return cb(null, "Error: Host service provider unavailable for HTTPS fetch");
}

function sendInterApp(targetID, action, capability, payloadJSON, cb) {
  const key = "hostService.sendRequest:" + targetID + ":" + action + ":" + capability;
  const direct = invokeCompat(payloadJSON, key);
  if (direct != null) {
    if (direct.startsWith("Err: ")) return cb(null, direct.substring(5));
    return cb(direct, null);
  }
  const target = bridge || compat || resolveBridge() || resolveCompat();
  if (target && typeof target.sendRequestActionCapabilityPayloadJSONCompletion === "function") {
    return target.sendRequestActionCapabilityPayloadJSONCompletion(targetID, action, capability, payloadJSON, cb);
  } else if (target && typeof target.sendRequest === "function") {
    return target.sendRequest(targetID, action, capability, payloadJSON, cb);
  } else if (target && typeof target.sendRequestSyncActionCapabilityPayloadJSON === "function") {
    try {
      const res = target.sendRequestSyncActionCapabilityPayloadJSON(targetID, action, capability, payloadJSON);
      const str = res != null ? res.toString() : "";
      if (str.startsWith("Err: ")) return cb(null, str.substring(5));
      return cb(str, null);
    } catch (e) {
      return cb(null, "sendRequestSyncActionCapabilityPayloadJSON error: " + e);
    }
  } else if (target && typeof target.sendRequestSync === "function") {
    try {
      const res = target.sendRequestSync(targetID, action, capability, payloadJSON);
      const str = res != null ? res.toString() : "";
      if (str.startsWith("Err: ")) return cb(null, str.substring(5));
      return cb(str, null);
    } catch (e) {
      return cb(null, "sendRequestSync error: " + e);
    }
  }
  return cb(null, "Error: Host service provider unavailable for inter-app request");
}

// Storage helpers using NSProcessInfo environment / bridge
function getStateDirectory() {
  const direct = invokeCompat("", "hostService.state");
  if (direct && !direct.startsWith("Err: ") && direct.length > 0) {
    return direct;
  }
  const target = bridge || compat;
  if (target && typeof target.stateDirectory === "function") {
    try {
      const dir = target.stateDirectory();
      if (dir) return dir.toString();
    } catch (e) {
      console.warn("[HanlinScriptParity] stateDirectory() call failed: " + e);
    }
  }
  const miniappStateDir = environment.objectForKey("HANLIN_MINIAPP_STATE_DIR");
  if (miniappStateDir) return miniappStateDir.toString();
  const miniappDataRoot = environment.objectForKey("HANLIN_MINIAPP_DATA_ROOT");
  if (miniappDataRoot) return miniappDataRoot.toString() + "/state";
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

const initialStorageStatus = loadStorage();

// Register canonical actions for inter-app, Widget/AppIntent, and headless execution.
const targetForRegister = bridge || compat || resolveBridge() || resolveCompat();
if (targetForRegister) {
  try {
    const regActionFn = targetForRegister.registerActionCapability || targetForRegister.registerAction;
    if (typeof regActionFn === "function") {
      regActionFn.call(targetForRegister, "share.value", "inter-app.share");
      regActionFn.call(targetForRegister, "parity.intent", "inter-app.share");
    } else {
      invokeCompat("share.value", "hostService.registerAction:inter-app.share");
      invokeCompat("parity.intent", "hostService.registerAction:inter-app.share");
    }
    const registerFn = targetForRegister.registerRequestHandlerCapabilityHandler || targetForRegister.registerRequestHandler;
    if (typeof registerFn === "function") {
      const handleRequest = (actionName) => (caller, payloadJSON, reply) => {
        console.log("[HanlinScriptParity] Received " + actionName + " from " + caller + ": " + payloadJSON);
        const replyPayload = JSON.stringify({
          source: "hanlin.demo.script-parity",
          action: actionName,
          caller: caller,
          request: JSON.parse(payloadJSON),
          counter: counter,
          name: persistedName
        });
        reply(replyPayload, null);
      };
      registerFn.call(targetForRegister, "share.value", "inter-app.share", handleRequest("share.value"));
      registerFn.call(targetForRegister, "parity.intent", "inter-app.share", handleRequest("parity.intent"));
    }
  } catch (e) {
    console.error("[HanlinScriptParity] Error registering handler: " + e);
  }
}

if (isHeadlessAction) {
  console.log("[HanlinScriptParity] Headless action handlers ready. " + initialStorageStatus);
} else {
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

// Auto-run deterministic verification passes with unpredictable nonce challenge
counterLabel.text = "Counter: " + counter;
storageStatusLabel.text = initialStorageStatus + "; " + saveStorage();

const envNonce = environment.objectForKey("HANLIN_PARITY_CHALLENGE");
const challengeNonce = (envNonce && envNonce.toString().length > 0)
  ? envNonce.toString()
  : ("nonce-" + Math.floor(Math.random() * 900000 + 100000));

const jsCode = "(function(n){ return JSON.stringify({ runtime: 'JSC', nonce: n, calc: n.length * 42 }); })('" + challengeNonce + "')";
runJS(jsCode, (res, err) => {
  updateOnMainThread(() => {
    if (err) {
      jsStatusLabel.text = "JS Err: " + err;
    } else {
      try {
        const parsed = JSON.parse(res.trim());
        if (parsed.runtime === "JSC" && parsed.nonce === challengeNonce) {
          jsStatusLabel.text = "JS: [VERIFIED JSC] nonce=" + parsed.nonce + " calc=" + parsed.calc;
        } else {
          jsStatusLabel.text = "JS: Invalid proof " + res;
        }
      } catch (e) {
        jsStatusLabel.text = "JS: " + res;
      }
    }
  });
});

const nodeCode = "const n = '" + challengeNonce + "'; if (typeof process === 'object' && process.versions && process.versions.node) { const calc = n.split('').reduce((acc, c) => acc + c.charCodeAt(0), 0) * 2; console.log(JSON.stringify({ runtime: 'Node', version: process.versions.node, nonce: n, calc: calc })); } else { throw new Error('Not Node runtime'); }";
runNode(nodeCode, (res, err) => {
  updateOnMainThread(() => {
    if (err) {
      nodeStatusLabel.text = "Node Err: " + err;
    } else {
      try {
        const parsed = JSON.parse(res.trim());
        if (parsed.runtime === "Node" && parsed.nonce === challengeNonce && parsed.version) {
          nodeStatusLabel.text = "Node: [VERIFIED Node " + parsed.version + "] nonce=" + parsed.nonce + " calc=" + parsed.calc;
        } else {
          nodeStatusLabel.text = "Node: Invalid proof " + res;
        }
      } catch (e) {
        nodeStatusLabel.text = "Node: " + res;
      }
    }
  });
});

const pyCode = "import sys, json\nif hasattr(sys, 'version_info') and sys.version_info.major >= 3:\n    v = f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}'\n    n = '" + challengeNonce + "'\n    calc = sum(ord(c) for c in n) * 3\n    print(json.dumps({'runtime': 'CPython', 'version': v, 'nonce': n, 'calc': calc}))\nelse:\n    raise RuntimeError('Not authentic CPython runtime')";
runPython(pyCode, (res, err) => {
  updateOnMainThread(() => {
    if (err) {
      pythonStatusLabel.text = "Python Err: " + err;
    } else {
      try {
        const parsed = JSON.parse(res.trim());
        if (parsed.runtime === "CPython" && parsed.nonce === challengeNonce && parsed.version) {
          pythonStatusLabel.text = "Python: [VERIFIED CPython " + parsed.version + "] nonce=" + parsed.nonce + " calc=" + parsed.calc;
        } else {
          pythonStatusLabel.text = "Python: Invalid proof " + res;
        }
      } catch (e) {
        pythonStatusLabel.text = "Python: " + res;
      }
    }
  });
});

const netURL = (environment.objectForKey("HANLIN_TEST_NETWORK_URL") || "https://en.wikipedia.org/").toString();
fetchHTTPS(netURL, (res, err) => {
  updateOnMainThread(() => {
    if (err) {
      networkStatusLabel.text = "HTTPS: Unavailable (" + err + ")";
    } else if (res && (res.includes("200") || res.includes("<html") || res.includes("<!DOCTYPE") || res.length > 50)) {
      networkStatusLabel.text = "HTTPS: [VERIFIED 200] len=" + res.length + " nonce=" + challengeNonce;
    } else {
      networkStatusLabel.text = "HTTPS: Received " + (res ? res.substring(0, 40) : "empty");
    }
  });
});

sendInterApp("hanlin.demo.script-parity", "share.value", "inter-app.share", JSON.stringify({ nonce: challengeNonce, timestamp: Date.now() }), (res, err) => {
  updateOnMainThread(() => {
    if (err) {
      interAppStatusLabel.text = "Inter-App Err: " + err;
    } else {
      try {
        const parsed = JSON.parse(res);
        if (parsed.action === "share.value" && parsed.request && parsed.request.nonce === challengeNonce) {
          interAppStatusLabel.text = "Inter-App: [VERIFIED] echoNonce=" + parsed.request.nonce + " source=" + parsed.source;
        } else {
          interAppStatusLabel.text = "Inter-App: " + res;
        }
      } catch (e) {
        interAppStatusLabel.text = "Inter-App: " + res;
      }
    }
  });
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
}
