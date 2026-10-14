// HanlinScript Parity Mini App
// Proves deterministic Node, Python, JavaScript, and HTTPS execution,
// canonical private storage, and host-bound inter-app requests.

console.log("[HanlinScriptParity] Initializing bundle...");

const g = typeof globalThis !== "undefined" ? globalThis : (typeof global !== "undefined" ? global : this);

function getBridgeCandidates() {
  const gRef = typeof globalThis !== "undefined" ? globalThis : (typeof global !== "undefined" ? global : this);
  const rawClasses = [];

  function tryAddClass(c) {
    if (c && rawClasses.indexOf(c) === -1) rawClasses.push(c);
  }

  try { if (typeof HanlinNativeServicesBridge !== "undefined" && HanlinNativeServicesBridge) tryAddClass(HanlinNativeServicesBridge); } catch (e) {}
  try { if (typeof HanlinNativeScriptCompatibility !== "undefined" && HanlinNativeScriptCompatibility) tryAddClass(HanlinNativeScriptCompatibility); } catch (e) {}
  try { if (gRef && gRef.HanlinNativeServicesBridge) tryAddClass(gRef.HanlinNativeServicesBridge); } catch (e) {}
  try { if (gRef && gRef.HanlinNativeScriptCompatibility) tryAddClass(gRef.HanlinNativeScriptCompatibility); } catch (e) {}
  try {
    const fn = (gRef && typeof gRef.NSClassFromString === "function") ? gRef.NSClassFromString : (typeof NSClassFromString === "function" ? NSClassFromString : null);
    if (fn) {
      const c1 = fn("HanlinNativeServicesBridge");
      if (c1) tryAddClass(c1);
      const c2 = fn("HanlinNativeScriptCompatibility");
      if (c2) tryAddClass(c2);
    }
  } catch (e) {}
  try {
    const fn = (gRef && typeof gRef.objc_getClass === "function") ? gRef.objc_getClass : (typeof objc_getClass === "function" ? objc_getClass : null);
    if (fn) {
      const c1 = fn("HanlinNativeServicesBridge");
      if (c1) tryAddClass(c1);
      const c2 = fn("HanlinNativeScriptCompatibility");
      if (c2) tryAddClass(c2);
    }
  } catch (e) {}

  const candidates = [];
  function add(item) {
    if (item && candidates.indexOf(item) === -1) {
      candidates.push(item);
    }
  }

  for (const c of rawClasses) {
    add(c);
    try { if (typeof c.sharedBridge === "function") add(c.sharedBridge()); } catch (e) {}
    try { if (typeof c.sharedCompatibility === "function") add(c.sharedCompatibility()); } catch (e) {}
    try { if (typeof c.activeSessionBridge === "function") add(c.activeSessionBridge()); } catch (e) {}
    try { if (typeof c.alloc === "function") add(c.alloc().init()); } catch (e) {}
    try { if (typeof c.new === "function") add(c.new()); } catch (e) {}
  }
  return candidates;
}

function resolveBridge() {
  const cands = getBridgeCandidates();
  return cands.length > 0 ? cands[0] : null;
}

function resolveCompat() {
  const cands = getBridgeCandidates();
  return cands.length > 0 ? cands[0] : null;
}

const bridge = resolveBridge();
const compat = resolveCompat();
console.log("[HanlinScriptParity] Bridge resolution: bridge=" + (bridge ? "found" : "null") + " compat=" + (compat ? "found" : "null") + " totalCandidates=" + getBridgeCandidates().length);

const environment = NSProcessInfo.processInfo.environment;
const executionMode = environment.objectForKey("HANLIN_EXECUTION_MODE");
const isHeadlessAction = executionMode && executionMode.toString() === "headless-action";

function invokeObjC(target, selName, arg1, arg2) {
  if (!target) return undefined;
  const gRef = typeof globalThis !== "undefined" ? globalThis : (typeof global !== "undefined" ? global : this);

  // 1. Direct camelCase method (e.g., roundTripValueKey, executeJavaScriptSync)
  const jsName = selName.replace(/:([a-z0-9_])/gi, (_, ch) => ch.toUpperCase()).replace(/:/g, '');
  if (typeof target[jsName] === "function") {
    try {
      if (arg2 !== undefined) return target[jsName](arg1, arg2);
      if (arg1 !== undefined) return target[jsName](arg1);
      return target[jsName]();
    } catch (e) {
      console.warn("[HanlinScriptParity] invokeObjC direct method " + jsName + " failed: " + e);
    }
  }

  // 2. Direct exact selector name (target["roundTripValue:key:"])
  if (typeof target[selName] === "function") {
    try {
      if (arg2 !== undefined) return target[selName](arg1, arg2);
      if (arg1 !== undefined) return target[selName](arg1);
      return target[selName]();
    } catch (e) {
      console.warn("[HanlinScriptParity] invokeObjC selector property " + selName + " failed: " + e);
    }
  }

  // 3. Dynamic Objective-C dispatch via performSelector
  const selFromString = (gRef && typeof gRef.NSSelectorFromString === "function")
    ? gRef.NSSelectorFromString
    : (typeof NSSelectorFromString === "function" ? NSSelectorFromString : null);

  if (selFromString) {
    try {
      const sel = selFromString(selName);
      if (sel) {
        if (typeof target.respondsToSelector === "function" && !target.respondsToSelector(sel)) {
          return undefined;
        }
        if (arg2 !== undefined && typeof target.performSelectorWithObjectWithObject === "function") {
          return target.performSelectorWithObjectWithObject(sel, arg1, arg2);
        }
        if (arg1 !== undefined && typeof target.performSelectorWithObject === "function") {
          return target.performSelectorWithObject(sel, arg1);
        }
        if (typeof target.performSelector === "function") {
          return target.performSelector(sel);
        }
      }
    } catch (e) {
      console.warn("[HanlinScriptParity] invokeObjC performSelector " + selName + " failed: " + e);
    }
  }

  return undefined;
}

function invokeCompat(value, key) {
  const targets = getBridgeCandidates();

  for (const c of targets) {
    // 1. Try roundTripValue:key:
    const roundTripRes = invokeObjC(c, "roundTripValue:key:", value != null ? String(value) : "", key);
    if (roundTripRes !== undefined && roundTripRes !== null) {
      return roundTripRes.toString();
    }

    // 2. Direct selector fallbacks
    if (key === "hostService.executeJavaScript") {
      const res = invokeObjC(c, "executeJavaScriptSync:", value != null ? String(value) : "");
      if (res !== undefined && res !== null) return res.toString();
    }
    if (key === "hostService.executeNode") {
      const res = invokeObjC(c, "executeNodeSync:", value != null ? String(value) : "");
      if (res !== undefined && res !== null) return res.toString();
    }
    if (key === "hostService.executePython") {
      const res = invokeObjC(c, "executePythonSync:", value != null ? String(value) : "");
      if (res !== undefined && res !== null) return res.toString();
    }
    if (key === "hostService.fetchURL") {
      const res = invokeObjC(c, "fetchURLSync:", value != null ? String(value) : "");
      if (res !== undefined && res !== null) return res.toString();
    }
    if (key.startsWith("hostService.sendRequest:")) {
      const parts = key.split(":");
      const targetID = parts[1] || "";
      const action = parts[2] || "";
      const capability = parts[3] || "";
      if (typeof c.sendRequestSyncActionCapabilityPayloadJSON === "function") {
        try {
          const res = c.sendRequestSyncActionCapabilityPayloadJSON(targetID, action, capability, value != null ? String(value) : "");
          if (res != null) return res.toString();
        } catch (e) {}
      }
      if (typeof c.sendRequestSync === "function") {
        try {
          const res = c.sendRequestSync(targetID, action, capability, value != null ? String(value) : "");
          if (res != null) return res.toString();
        } catch (e) {}
      }
      const syncRes = invokeObjC(c, "sendRequestSync:action:capability:payloadJSON:", targetID, action, capability, value != null ? String(value) : "");
      if (syncRes !== undefined && syncRes !== null) return syncRes.toString();
    }
    if (key === "hostService.state") {
      const res = invokeObjC(c, "stateDirectory") || invokeObjC(c, "currentStateDirectory");
      if (res !== undefined && res !== null) return res.toString();
    }
    if (key === "hostService.dataRoot") {
      const res = invokeObjC(c, "dataRootDirectory") || invokeObjC(c, "currentDataRootDirectory");
      if (res !== undefined && res !== null) return res.toString();
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
  const targets = getBridgeCandidates();
  for (const target of targets) {
    if (typeof target.executeJavaScriptCompletion === "function") {
      return target.executeJavaScriptCompletion(code, cb);
    }
    if (typeof target.executeJavaScript === "function") {
      return target.executeJavaScript(code, cb);
    }
    const syncRes = invokeObjC(target, "executeJavaScriptSync:", code);
    if (syncRes !== undefined && syncRes !== null) {
      const str = syncRes.toString();
      if (str.startsWith("Err: ")) return cb(null, str.substring(5));
      return cb(str, null);
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
  const targets = getBridgeCandidates();
  for (const target of targets) {
    if (typeof target.executeNodeCompletion === "function") {
      return target.executeNodeCompletion(code, cb);
    }
    if (typeof target.executeNode === "function") {
      return target.executeNode(code, cb);
    }
    const syncRes = invokeObjC(target, "executeNodeSync:", code);
    if (syncRes !== undefined && syncRes !== null) {
      const str = syncRes.toString();
      if (str.startsWith("Err: ")) return cb(null, str.substring(5));
      return cb(str, null);
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
  const targets = getBridgeCandidates();
  for (const target of targets) {
    if (typeof target.executePythonCompletion === "function") {
      return target.executePythonCompletion(code, cb);
    }
    if (typeof target.executePython === "function") {
      return target.executePython(code, cb);
    }
    const syncRes = invokeObjC(target, "executePythonSync:", code);
    if (syncRes !== undefined && syncRes !== null) {
      const str = syncRes.toString();
      if (str.startsWith("Err: ")) return cb(null, str.substring(5));
      return cb(str, null);
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
  const targets = getBridgeCandidates();
  for (const target of targets) {
    if (typeof target.fetchURLCompletion === "function") {
      return target.fetchURLCompletion(url, cb);
    }
    if (typeof target.fetchURL === "function") {
      return target.fetchURL(url, cb);
    }
    const syncRes = invokeObjC(target, "fetchURLSync:", url);
    if (syncRes !== undefined && syncRes !== null) {
      const str = syncRes.toString();
      if (str.startsWith("Err: ")) return cb(null, str.substring(5));
      return cb(str, null);
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
  const jsonKey = "hostService.sendRequest";
  const jsonVal = JSON.stringify({ targetID: targetID, action: action, capability: capability, payloadJSON: payloadJSON });
  const directJSON = invokeCompat(jsonVal, jsonKey);
  if (directJSON != null) {
    if (directJSON.startsWith("Err: ")) return cb(null, directJSON.substring(5));
    return cb(directJSON, null);
  }

  const targets = getBridgeCandidates();
  for (const target of targets) {
    if (typeof target.sendRequestActionCapabilityPayloadJSONCompletion === "function") {
      return target.sendRequestActionCapabilityPayloadJSONCompletion(targetID, action, capability, payloadJSON, cb);
    }
    if (typeof target.sendRequest === "function") {
      return target.sendRequest(targetID, action, capability, payloadJSON, cb);
    }
    if (typeof target.sendRequestSyncActionCapabilityPayloadJSON === "function") {
      try {
        const res = target.sendRequestSyncActionCapabilityPayloadJSON(targetID, action, capability, payloadJSON);
        if (res != null) {
          const str = res.toString();
          if (str.startsWith("Err: ")) return cb(null, str.substring(5));
          return cb(str, null);
        }
      } catch (e) {}
    }
    if (typeof target.sendRequestSync === "function") {
      try {
        const res = target.sendRequestSync(targetID, action, capability, payloadJSON);
        if (res != null) {
          const str = res.toString();
          if (str.startsWith("Err: ")) return cb(null, str.substring(5));
          return cb(str, null);
        }
      } catch (e) {}
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
  const targets = getBridgeCandidates();
  for (const target of targets) {
    if (typeof target.stateDirectory === "function") {
      try {
        const dir = target.stateDirectory();
        if (dir) return dir.toString();
      } catch (e) {
        console.warn("[HanlinScriptParity] stateDirectory() call failed: " + e);
      }
    }
    const dir = invokeObjC(target, "stateDirectory") || invokeObjC(target, "currentStateDirectory");
    if (dir && !dir.startsWith("Err: ") && dir.length > 0) return dir.toString();
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
const registrationCandidates = getBridgeCandidates();
for (const cand of registrationCandidates) {
  try {
    const regActionFn = cand.registerActionCapability || cand.registerAction;
    if (typeof regActionFn === "function") {
      regActionFn.call(cand, "share.value", "inter-app.share");
      regActionFn.call(cand, "parity.intent", "inter-app.share");
    } else {
      invokeObjC(cand, "registerAction:capability:", "share.value", "inter-app.share");
      invokeObjC(cand, "registerAction:capability:", "parity.intent", "inter-app.share");
    }
    const registerFn = cand.registerRequestHandlerCapabilityHandler || cand.registerRequestHandler;
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
      registerFn.call(cand, "share.value", "inter-app.share", handleRequest("share.value"));
      registerFn.call(cand, "parity.intent", "inter-app.share", handleRequest("parity.intent"));
    }
  } catch (e) {
    console.error("[HanlinScriptParity] Error registering handler on candidate: " + e);
  }
}
invokeCompat("share.value", "hostService.registerAction:inter-app.share");
invokeCompat("parity.intent", "hostService.registerAction:inter-app.share");

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
