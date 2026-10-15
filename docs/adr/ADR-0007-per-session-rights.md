# ADR-0007 — Per-session rights: identity by consent, carried token, multi-host consent (backlog item 0076)

**Date**: 2026-08-15  
**Status**: proposed (Phase A targeted by backlog item 0076; Phases B/C = *sovereign mobile access* axis, ADR-0008 / PR #109)  
**Decision makers**: Thomas (maintainer)

> **TL;DR** — Each conversation gets a Google scope **of its own**: decided by a **signed human consent action** (ADR-0005 elicitation **required**; not inferred from the MCP connection), **carried in every call** (not in a global server state), **configurable at the finest grain** (service × operation × resource), and **validatable from the device where the human is** (desktop Touch ID or Android biometrics, including remotely). Result: two sessions of the same account can have different rights, and none passively inherits from another. *The tool verifies, the human authorizes, the LLM proposes.*

## Context

Backlog item 0045 set the intent ("each session starts from zero, with its own isolated rights"). Phase A was plumbed into the code (`gateway/sessions.py`, `.sessions/` registry, `mag session …`), but observation of the workstation shows it is **wired up empty**:

- **The grain is the MCP connection, not the conversation.** The `session_id` is minted at `initialize` and set in a **process global** (`gateway/context.py:set_session_id`). Yet Claude Desktop shares **one** MCP connection across all its conversations → a single `session_id` for everyone.
- **Rights are coarse**: account-level `unlock` + Drive zones. No differentiation by service / operation / resource.
- **Two bugs observed** (7 sessions read on the workstation, 14/08): `last_seen_at == created_at` everywhere (the activity `touch()` does not fire → inactivity-based TTL is dead) and sessions **accumulate with no effective purge** (dead TTL; no revocation).

Forces at play:

- The **MCP protocol does not transmit** a conversation identifier; we cannot rely on it.
- Everything is **100% local**; the model stays **cooperative** as long as the vault (backlog item 0003) does not isolate the credentials.
- **Signed elicitation** already exists on the desktop side (backlog item 0001 / ADR-0005: canonical payload + ECDSA P-256, nonce anti-replay). We reuse it, we do not reinvent it.
- Broadened product target: validate **where the human is** (desktop **or** Android), with the desktop possibly switched off.

## Decision

1. **Identity by consent, not by connection.** A session is born from a **human action** ("open access for this chat") that issues a **signed session token** (reuses ADR-0005). **Session creation always goes through the signed elicitation path, regardless of the global `.strong-auth` flag** — no session without a signed action (enrollment required). **Each capability (unlock, fine-grained grant) — at creation as at widening — is carried by a signed consent binding the exact scope (account / service / operation / resource); no unsigned widening.** **Delegated sub-sessions** (`parent_session_id`) inherit a subset of the parent that is **already signed** — without a new signature — and **cannot widen** (no child `access_request`; cascading revocation), in line with backlog item 0045. The token is no longer derived from `initialize`.
2. **Token carried in every call.** The MCP tools accept a session parameter; the broker authorizes based on the **presented token**, never on a process global. *This is what isolates two conversations on a shared Desktop connection.* We drop the global `set_session_id`.
3. **Fine-grained rights configuration.** The session registry becomes a **capability document**: per (account, **service × operation × resource**), with expiry. Effective rights = **account policy ∩ project manifest ∩ session capabilities** (intersection, *fail-closed*). In the **absence of a valid project manifest** (outside a git repository, or a repo without a signed manifest), the project ceiling is **omitted**: effective rights = **policy ∩ session** — the manifest is an *optional* ceiling, never a floor (resolves open question no. 5 of 0045). **Anti-downgrade**: this omission applies only to a **never-configured** context (no manifest); a manifest that is **present-but-invalid, tampered with, or deleted after having been trusted** → **fail-closed (refusal)**, never a silent downgrade to `policy ∩ session` (defends S-07; trust remembered by `project_id`). The **resource** is **specific to the service** and **optional**: Drive = folder / zone (required for writing), Gmail = label (optional), Calendar = calendar (optional); **absent resource = service scope bounded by the account policy** (never a wildcard beyond it). The tool → (operation, resource) mapping is fixed at implementation.
4. **Multi-host, routable consent.** The broker + credentials live on the **host that is powered on** (desktop by default, Android otherwise). Biometric validation happens **where the human is**: desktop Touch ID **or** Android biometrics — including **remotely** (the desktop broker requests a signed approval from the **paired** phone). Keys in **Secure Enclave / Android Keystore**, paired devices.
5. **Lifecycle & observability.** A session's lifecycle is **decoupled from the MCP connection**: **TTL** expiration + **explicit revocation** (`mag session close` / `revoke`). **MCP disconnection is not a lifecycle signal**: since tokens are *bearer* tokens and the protocol provides no conversation identifier, the server cannot know at disconnection which tokens belong to which conversation — it therefore **purges no token** (end of life = TTL or explicit revocation only). `mag session list` + **per-session config view**; enriched audit log (`session_id`, service / operation / resource); `last_seen` advances on every call.
6. **Phasing.** **A — desktop** (backlog item 0076, this PR): local action + carried token + fine-grained config + `session list` + bug fixes. **B & C — mobile**: bringing the per-session rights model to **mobile** (remote consent, Android host) belongs to the **sovereign mobile access** axis (ADR-0008 / epic 0077, PR #109) — *remote consent* = the **passkey approval**, the *Android host* = the **native holder**; **conditioned on the vault** (0003).

## Options considered

**Birth of the identity**

| Option | Complexity | Client portability | Security | Verdict |
|---|---|---|---|---|
| **Signed consent action** | medium | all topologies | strong (signed, human) | **chosen** |
| Conversation id transmitted by the client | low | depends on the client (Desktop does not emit it) | medium | rejected — not guaranteed, not portable |
| Per MCP connection (current) | already done | fails on shared Desktop | weak | rejected — does not isolate conversations |

**Transport of the right**: *token carried in the call* (**chosen**) vs *process global* (current — broken as soon as a connection is shared).

**Granularity**: *service × operation × resource* (**chosen** — "each session its own config") vs *whole service* (too coarse) vs *account* (current).

**Desktop-off case**: *broker on Android, credentials local to the phone* (**chosen, phase C**) vs *cloud-side credentials* (rejected — breaks the 100% local and the "maximally secure" posture).

## Consequences

**Easier**: two sessions of the same account with distinct rights; new conversation = zero rights; per-session revocation; per-session audit; mobile extension framed.

**Harder**: the consent action adds friction (accepted; **Touch ID enrollment required to open any session**); the carried token requires a **session parameter on the tools** and that the model presents it (to be instructed on the skill / prompt side); remote consent is a costly **pairing protocol** (phase B); the Android host **doubles the credentials surface** (phase C) — to be done **only with** the vault (0003).

**To revisit**: the token is a **bearer capability** → bound it (short expiry, minimal scope, not displayed across conversations); everything stays **cooperative** until the vault is there (bare `gws` / filesystem editing bypasses, S-01…S-03 of 0045); if a client eventually exposes a real conversation id, it could be used as a **shortcut** for the action.

## Fallback (fail-closed) & limits

- Token missing / invalid / expired → **refusal** (never access by default).
- **Session creation without enrollment** of the elicitation key, or **biometrics unavailable** → **refusal** (`mag elicitation enroll`) — *no session without a signed action*, regardless of the `.strong-auth` flag.
- **MCP disconnection**: is **not** a lifecycle signal — bearer tokens + no observable conversation id, so it purges **no** token; end of life = **TTL or explicit revocation** (see Decision 5).
- **Service or operation** not declared in the session config → **refusal** (default-deny). **Absent resource** = service scope **bounded by the account policy** (see Decision 3), never beyond.
- **Scope widening without signed consent** → **refusal**: the broker grants a capability only if it is covered by a **signed payload** (account / service / operation / resource), regardless of `.strong-auth`. The model cannot self-widen up to the account / project ceilings.
- **Bootstrap without a token**: a call **without a token** opens **no data**; it can only trigger the **signed elicitation for session creation**, which delivers the token **after success** (`mag session open` / `access_request`).
- Remote consent (phase B): refusal if not paired, signature unverified, or request not bound to the exact action (nonce + expiry + device pinning).
- Threat limit **unchanged**: without the vault (0003), an agent with a shell can bypass (editing `.sessions/`, bare `gws`). The session layer **hardens the cooperative model**, it does not make it cryptographically watertight.

## Action items

1. [ ] **Phase A** — `session` parameter on the tools + token-based broker authorization; capability registry (service × op × resource) **signed at each grant**; `mag session list` + config view; purge + `last_seen` fix; **sub-agent inheritance ⊆ parent + cascading revocation (0045) tested**; hermetic tests green.
2. [ ] **Live Desktop** test (2 conversations → number of `session_id`s) to document, even though decision 2 makes it non-blocking.
3. [ ] **Phases B/C (mobile)** — bring the per-session rights model onto the **sovereign mobile access** axis (ADR-0008 / epic 0077, PR #109): remote consent = passkey approval; Android host = native holder; **conditioned on the vault** (0003).

## References

- Backlog items (in the repository): `features/0045-capacites-projet-signees.md`, `features/done/0076-droits-par-session-phase-a.md`, `features/0001-elicitation-signee-strongauth-v2.md`, `features/0003-vault-credentials-hors-perimetre-agent.md`
- ADR: [ADR-0005](ADR-0005-signed-elicitation-v2.md) (signed elicitation reused); ADR-0008 *sovereign mobile access* (PR #109) carries phases B/C.
- Code: `gateway/sessions.py`, `gateway/context.py`, `gateway/broker_server.py`, `gateway/mcp_server.py`
- Threat: `docs/threat-model.md`, `SECURITY.md`
