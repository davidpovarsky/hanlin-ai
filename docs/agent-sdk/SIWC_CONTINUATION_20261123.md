# ChatGPT plan usage — canonical Hanlin continuation (2026-11-23)

Source baseline: `1f9efa441b96fd02b3ee348cb9730d06b79dea0a`.
Scope: shared Hanlin OAuth credentials and the existing Responses/agent pipeline. Lorvex UI, server data, Apple signing and physical-device acceptance are owned by the host project.

## Integration

Use `apiType: "openai-chatgpt-plan"`, `company: "OPENAI"`, the public endpoint `https://api.openai.com/v1/responses`, the selected account access token and a model slug from that account's live catalog. `supportsToolUse: true` retains the canonical Hanlin tool executor and approval policy. Generic `openai-responses` remains available independently.

`HanlinChatGPTPlanClient.makeAttempt(hostID:loopbackPort:previous:appName:registration:)` accepts the actual host app name. Persist the host ID before opening the system browser. Retain `HanlinChatGPTPlanRegistration(credentials:)` separately after sign-out; it contains only client ID, verified subject and optional email. Pass the selected registration on later sign-in, without retaining removed access/refresh/ID tokens. Keep each issued client ID and verified subject together. The client validates callback uniqueness/state/client ID, PKCE, signed OIDC identity and scopes. It serializes rotating refresh tokens, validates refreshed identities and offers `revoke(_:)`. Hosts atomically persist the returned token set in Keychain, invalidate their active UI/request generation before sign-out and report any remote revocation failure. A granted plan scope is necessary but does not prove remaining quota or model availability.

The transport groups local function/custom definitions in the supported `hanlin` namespace, retains full stateless history and exact tool-argument strings, maps system instructions to developer input, and strips unsupported preview fields. It forwards unchanged complete SSE events to the original provider; success requires `response.completed`. Quota failures, incomplete responses, unknown tool namespaces and interrupted streams fail explicitly. This is a wire adaptation, not a second AI engine.

## Validation and impact

Changed consumer closure: HanlinChatCore SIWC auth, Responses provider selection, agent initial tools/settings and the SIWC-only fetch adapter. Other providers and generic Responses do not use the SIWC transport. Existing generic/agent tests remain relevant; no broad suite result is claimed here.

Executed: six production wire checks on Windows Swift 6.3.3 (Swift 6 mode), 2026-11-23 UTC. These compile the actual `HanlinChatGPTPlanWire.swift`, not a reimplementation: request namespace/stateless history and large integer argument preservation; UTF-8 byte fragmentation with exact event preservation; missing completion; quota failure; incomplete response; wrong namespace. Git diff whitespace check passed.

Native checks to execute in the host's existing Apple runner (no additional Apple build dispatch):

```bash
swiftc -swift-version 6 -parse-as-library \
  Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinChatGPTPlanClient.swift \
  Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinChatGPTPlanWire.swift \
  Scripts/Tests/verify_chatgpt_plan_contract.swift \
  -o "$RUNNER_TEMP/verify-chatgpt-plan"
"$RUNNER_TEMP/verify-chatgpt-plan"
```

The same executable adds eight Apple CryptoKit/Security URLProtocol fixture checks: PKCE/app identity, signature-verified sign-in, rejected duplicate callback without token exchange, concurrent refresh/rotation/reduced grants, account model visibility, revocation, token-free returning registration/current-host continuity, and rejection of a different signed subject. It performs no live account request. The canonical `HanlinChatGPTPlanTests` suite adds the production Hanlin agent namespaced-tool → actual fixture effect → tool result → final text continuation; it must execute in a configured HanlinChatCore test target. These native checks are NOT_RUN until the host run records their results.

Still requires real-user OAuth consent, account/workspace eligibility and successful live Responses inference, plus host rendering/physical-device validation. A public documentation contract and local fixtures are not a live entitlement test.

## Official contract checked

- https://developers.openai.com/siwc/token-sharing-open-source
- https://developers.openai.com/siwc/token-sharing-open-source/sign-in
- https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions
- https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference
- https://developers.openai.com/siwc/token-sharing-open-source/token-reference
- https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations
- https://developers.openai.com/api/docs/guides/function-calling
- https://developers.openai.com/api/reference/resources/responses/methods/create

The open-source/local flow uses dynamic registration without a partner secret. Paid or remotely hosted offerings follow OpenAI's separate interest/registration path. Access tokens are not ChatGPT cookies; the app does not acquire conversation history.
