HTTP capture scripts let you rewrite matching requests and responses with JavaScript while capturing traffic. A script is attached to a **capture rule** and runs inside the capture engine when the rule's pattern matches a request URL.

> These APIs (`$request`, `$response`, `$done`, `$argument`, `console`, `$httpClient`, `$persistentStore`, `$notification`, `$utils`) are available **only inside capture rule scripts** — not in regular scripts, and they are not imported.

---

## Rule configuration

Each rule is configured in the rule editor:

| Field | Meaning |
| ----- | ------- |
| **Pattern** | A regular expression matched against the request URL. The script runs only when it matches. |
| **Type** | `Request` runs before the request is sent; `Response` runs after the response is received. |
| **Requires Body** | When on, the message body is buffered so the script can read and rewrite it. When off, the script sees headers only. |
| **Max Body Size** | Bodies larger than this pass through untouched (the script is skipped for that message). |
| **Binary Body** | When on, `body` is exposed as a `Uint8Array`; when off, as a string. |
| **Timeout** | If the script does not call `$done(...)` within this many seconds, the message passes through unchanged. |
| **When the script cannot decide** | Whether the traffic is let through (the default) or refused when the script produces no decision. See [below](#when-a-script-cannot-decide). |
| **Argument** | A value exposed to the script as `$argument`. |

---

## Execution model

When several rules match the same message, they run **in the order they appear in the list**, and the effects accumulate: each script sees the output of the previous one. A request script that returns a mock response (see below) short-circuits the chain — no upstream request is made and no response scripts run.

If a script throws, times out, or never calls `$done(...)`, the message passes through unchanged — a script that breaks does not take the traffic down with it. A rule can opt out of that when being bypassed is the worse outcome; see below.

---

## When a script cannot decide

By default a rule that produces no decision lets the traffic through untouched. That is the right default for most scripts: a typo in one of them should not cut off the app it matches.

It is the wrong default for a rule whose entire purpose is to change the traffic — one that attaches credentials, strips a field, or blocks something. There, "let it through unchanged" means the rule quietly did nothing, and nothing at the other end can tell. For those rules set **When the script cannot decide** to **Refuse traffic**, or write `failure-policy=reject` on the rule in a module.

### What counts as not deciding

More than the script throwing. All of these are cases where a rule was supposed to run and did not:

* the script threw, including a syntax error;
* the script never called `$done(...)` and reached its Timeout;
* the script could not be started, or the engine was not available;
* the rule has no script body at all — a module rule whose script never downloaded (see the next section);
* the body is larger than this rule's **Max Body Size**;
* the body could not be buffered: the response is streamed one piece at a time, or it is over the buffer limit for the whole message, or too much traffic is being held for scripts at that moment.

The last one is worth reading twice. **When a body cannot be buffered, no rule on that message runs** — including rules that only look at headers and never needed the body. So it is the case most likely to leave a rule silently bypassed, and it happens on exactly the large transfers you would most want a rule to see.

### What refusing does

| Rule type | Refusing means |
| --------- | -------------- |
| **Request** | The request is never sent to the server. The app gets a **403** produced on this device. |
| **Response** | The server's response is not delivered. The app gets the same **403** in its place. |

Both directions answer 403 rather than 502: the server is not the thing that failed, a local rule is. And a response is replaced rather than the connection being dropped, because a dropped connection is indistinguishable from the network failing — a 403 can at least be recognised.

The 403 body is plain text. It names the rule and says what happened. It carries nothing else — not the URL, not the script's path, not anything the script produced. That body reaches the app and is kept in the capture record, so nothing that came from the script is allowed into it.

**Which rule decides.** When a rule's own script fails — it threw, timed out, has no body to run, or the body is over *that rule's* Max Body Size — that rule's own setting decides. When the message body could not be buffered at all, nothing on the message ran, so the message is refused if **any** rule on it is set to refuse.

### In a module

Write it as a key on the script line, alongside `script-path` and the rest:

```
failure-policy=reject
```

Anything other than `reject` or `passthrough` is reported when the module is imported, and the rule keeps the default.

> **`failure-policy` is this app's own key.** Other apps that read this module format do not have it. A module that uses it behaves as described here; what another app does with the key — ignore it, warn, or reject the module — is not something this app can promise.

It applies to request and response rules only. `failure-policy=reject` on a timed, event, DNS, or rule-matching script is reported and ignored at import time: those have no traffic to refuse, and "refuse" would mean something different for each of them.

### Streaming rules

A rule with a frame codec always lets traffic through when its script cannot decide, and the setting is disabled for it. By the time such a script runs, the response is already on its way to the app — there is nothing left to refuse.

---

## Scripts that come from a module

A module declares its scripts with `script-path`. When the module is imported or updated, each of those is downloaded and a **copy is kept on this device**. That copy is what runs — changing the file on the server has no effect until the module is updated again.

**If a script cannot be downloaded, the rule is still created, but it has no script body.** It matches and runs nothing — which looks exactly like a rule that works but had nothing to change. What "nothing" means depends on the rule: a request rule sends the request unchanged, a response rule delivers the response unchanged, a timed rule has nothing to run when its schedule comes around, and a rule-matching script is treated as not matching. Three places tell you which it is:

* the module list says how many of its rules have no script body;
* the module's details page says, per rule, where its script came from, how large it is, and when it was last updated — or that it could not be downloaded, and from where;
* the script log records every download and every failure with the reason (category `fetch`).

A rule set to refuse traffic is the exception: with no script body it answers 403 rather than running nothing, which is the point of setting it. See [When a script cannot decide](#when-a-script-cannot-decide).

Two more things worth knowing:

* Rules that came from a module are read-only. Duplicate the module to a local copy if you want to edit them.
* Two rules that declare the **same** `script-path` share one `$persistentStore` default slot — that is what makes the common "one timed script refreshes a token, one request rule uses it" pattern work. See [`$persistentStore`](capture_scripts_store/en.md).

---

## `$request`

Available in both request and response scripts.

```ts
$request: {
  url: string
  method: string
  headers: Record<string, string>
  body?: string | Uint8Array   // present only when Requires Body is on
}
```

In a response script, `$request` is read-only and exposes `url` and `method` for context.

## `$response`

Available in response scripts.

```ts
$response: {
  status: number
  headers: Record<string, string>
  body?: string | Uint8Array   // present only when Requires Body is on
}
```

The body is already decompressed: if the response used `Content-Encoding` such as gzip, `body` is the decoded content. Use [`$utils.ungzip`](capture_scripts_utils/en.md) only for data that is gzip-compressed at the application layer.

---

## `$done`

Every script must call `$done(...)` exactly once to finish. The shape of the argument determines the outcome.

### Request scripts

```ts
// Pass through unchanged
$done({})

// Rewrite the outgoing request (any field may be omitted)
$done({
  url?: string,
  headers?: Record<string, string>,
  body?: string | Uint8Array,
})

// Return a mock response without contacting the server (short-circuits the chain)
$done({
  response: {
    status: number,
    headers?: Record<string, string>,
    body?: string | Uint8Array,
  }
})
```

### Response scripts

```ts
// Pass through unchanged
$done({})

// Rewrite the response (any field may be omitted)
$done({
  status?: number,
  headers?: Record<string, string>,
  body?: string | Uint8Array,
})
```

When you return `headers`, they replace the header set that is forwarded. Omit `headers` to keep the original ones.

---

## `$argument`

The value configured on the rule. For a plain argument it is a string; for a structured argument (input / select / switch fields) it is an object keyed by field name.

```ts
// Rule argument: token=abc123
const token = $argument            // "abc123"

// Structured argument
const enabled = $argument.enabled  // true
```

---

## `console`

```ts
console.log(...args: any[]): void
```

`console.log` writes to the capture log for debugging.

---

## Example

```js
// Request script: inject a header and add a query flag.
const headers = $request.headers
headers["X-Debug"] = "1"
$done({ url: $request.url + "?trace=1", headers })
```

```js
// Response script (Requires Body on): add a field to a JSON response.
try {
  const json = JSON.parse($response.body)
  json.injected = true
  $done({ body: JSON.stringify(json) })
} catch (e) {
  $done({})
}
```

## Related APIs

* [`$httpClient`](capture_scripts_httpclient/en.md) — send HTTP requests from a script.
* [`$persistentStore`](capture_scripts_store/en.md) — read and write persistent values.
* [`$notification`](capture_scripts_notification/en.md) — post a local notification.
* [`$utils`](capture_scripts_utils/en.md) — utility helpers (`ungzip`, …).
