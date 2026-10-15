# ADR-0008: Mobile access — passkey approval, held by a sovereign native "holder"

**Status:** Accepted
**Date:** 2026-08-14 (accepted on 2026-08-15)
**Deciders:** Thomas (PO)
**Note:** renumbered from ADR-0007 on 2026-08-15 — number 0007 was taken by the "per-session rights" ADR (PR #108), a separate topic.

> **TL;DR** — To reach your Google accounts from a phone — **even when the Mac is off** — without ever handing your access tokens to a third-party service, we split three roles: **who asks** for an action (the AI assistant, wherever it runs), **who approves** it (always the phone, through a fingerprint that **signs** the precise action using a *passkey* — the standard supported on macOS/Windows/Linux/Android/iOS), and **who actually holds** the access (a native "holder" component that **seals the tokens in the device's hardware vault** — Secure Enclave, StrongBox — with a non-exportable key). Without an always-on server, the **phone itself** becomes that holder, **on demand** (nothing runs in the background). The project is now redesigned as **free software**, which rules out any centralized control point: the only possible relay is **blind** (it only sees signatures, never a token) and **self-hostable**.

## Context

Today the whole system is **local to one Mac**:

- The MCP server is **stdio** (`gateway/mcp_server.py`): launched as a child process by the LLM client, on the same machine. No network listener.
- Tokens live in a **local encrypted vault** (`GWSA_ROOT/.vault/<alias>/credentials.enc`), served by a **loopback broker** `127.0.0.1:4878`.
- Approval of a sensitive action (unlock, grant, add) goes through the **web admin `127.0.0.1:4877`** — which has **no application-level authentication**: it trusts the macOS session. Being physically in front of the unlocked Mac **is** the authorization (*ambient* authority).
- Under `strongauth`, consent is **signed** (Touch ID → ECDSA P-256, anti-replay nonce, verifiable receipt) — see [ADR-0005](ADR-0005-signed-elicitation-v2.md). The key lives in the **Secure Enclave *when available***; the Swift helper otherwise falls back to the software Keychain, then to an **exportable** `private.p256` file — so the "enclave" guarantee is **not** universal today.

The new need (session of 2026-08-13): **use these accounts from a mobile phone**, in contexts where the agent runs somewhere other than the Mac (Claude Code remote, a Claude chat, cowork, Anthropic's cloud environment), **with the Mac on or off**, and **without a personal device that is always on**.

Three forces pull against each other:

1. **The project's DNA**: 100% local, tokens never handed to a third party, audit and per-service lock (default-deny).
2. **Mobile reality**: the phone has no "macOS session" to trust; ambient authority does not exist; a *cloud* agent must be assumed **potentially hostile**.
3. **No server**: without a machine on 24/7, there is no "backend" that survives the Mac being switched off — **except the phone**, the only personal device always with you and on.

## Decision

Adopt a **three-role decoupled** model, and rebuild the holding/approval component around cross-platform standards.

1. **Three roles.**
   - **Requester** — the LLM agent that *asks* for an action. Anywhere (local, remote, cloud). **Never trusted** by construction.
   - **Approver** — **the phone**, always. It *approves* by **signing** the exact description of the action with a **passkey** (WebAuthn/FIDO2), guarded by biometrics (Face ID / Touch ID / Hello / Android biometrics).
   - **Holder** — the component that *holds* the tokens and *executes* the Google calls. It acts only when presented with a **valid signed approval**.

2. **Approval becomes a passkey signature** — a generalization of [ADR-0005](ADR-0005-signed-elicitation-v2.md). The signer **migrates** from the Mac's Secure Enclave to the **phone's passkey**. A single standard API replaces the macOS-only Swift helper, and covers all 5 OSes.

3. **WYSIWYS — "what you see is what you sign".** The phone **displays the precise action before signing** ("Allow Drive · personal account · folder *X* · 2 h?"). The signed challenge binds the consent to that action (account, target, duration, `nonce`, `expires_at`). A compromised cloud requester **cannot** get anything signed other than what the human sees.

4. **Maximum security at rest: native holder, tokens sealed in the hardware vault.** Tokens are encrypted by a **non-exportable** key kept in the device's hardware vault (iOS/macOS Secure Enclave, Android StrongBox/Keystore, TPM), unsealed only after biometrics. We abandon the "browser" route (PWA): the PO's priority is **security at rest**, not speed of implementation.

5. **No 24/7 server: the phone is the holder when the Mac is off** — as an **ephemeral on-demand holder**. No daemon: open the app → biometrics → unseal → Google call → forget. The Mac remains a possible holder **when it is on** (the existing setup keeps serving).

6. **Chosen technology: Tauri 2 (Rust core, embedded web UI)** for the native holder/approver — covers all 5 OSes, small auditable binary, native access to hardware vaults, reduced attack surface. *Flutter* is the documented alternative (see Options).

7. **Free software, therefore zero centralized control point.** The only possible relay (to reach a holder behind a NAT from a cloud agent) is **blind** — it carries **end-to-end encrypted envelopes**, opaque to it, in **both directions** (requests/challenges *and* results); it never sees a token or any plaintext content — and **self-hostable**. Each user supplies **their own OAuth client** (already the case through GCP provisioning). No shared secret enters the repository.

8. **Complementary decisions (settled on 2026-08-15 with the PO).**
   - **Per-device OAuth enrollment**: each device (Mac, phone) holds its own tokens in its own vault — **no** secret synchronization between devices.
   - **Gradual migration, no big bang**: the existing **Python-macOS** holder is **kept** and continues to serve; the native holder is added **alongside** it. Any eventual unification of the desktop on Tauri 2 is **deferred** (not decided).
   - **License: ~~Apache-2.0~~ → MIT** *(corrected on 2026-09-04: the repository's actual license is **MIT** — see `LICENSE` and the delivered backlog item 0016. The Apache-2.0 choice considered here was not retained at open-source delivery.)*
   - **Starting point = phase 1**: put passkey approval on the *current* architecture (Mac holder on) before any native rebuild.

## Options considered

### Axis 1 — Where does the holder live (token holding + execution)?

#### Option 1A — Status quo: the Mac, sole holder
| Dimension | Assessment |
|---|---|
| "Mac off" | ❌ no access |
| Sovereignty | ✅✅ maximal (nothing changes) |
| Cost | 🟢 none |

**Rejected**: does not meet the "Mac on *or off*" requirement.

#### Option 1B — An always-on personal device (Pi, NAS, Mac mini)
| Dimension | Assessment |
|---|---|
| "Mac off" | ✅ the server holds |
| Sovereignty | ✅ (your own machine) |
| Cost | 🟠 a server to administer + inbound transport + remote biometrics |

**Rejected**: the PO **does not have** and does not want an always-on device.

#### Option 1C — A holder in the cloud (Anthropic or a third party)
| Dimension | Assessment |
|---|---|
| "Mac off" | ✅ |
| Sovereignty | ❌ Google tokens handed to a third party, in cleartext at time of use |
| Cost | 🟢 light |

**Rejected**: betrays the project's DNA. "No MCP at all" (a generic Google connector) is a degraded case of this one — it loses multi-account, policy, lock and audit, that is **all the value**.

#### Option 1D — The phone becomes the holder (chosen)
| Dimension | Assessment |
|---|---|
| "Mac off" | ✅ the phone is the always-on device |
| Sovereignty | ✅✅ nothing leaves the user's devices |
| Cost | 🔴 core rebuild (leaves Python + `gws` CLI + macOS Swift) |

**Chosen**: the only option that reconciles "Mac off", sovereignty and no server. The price — the native rebuild — is accepted.

### Axis 2 — Technology of the native holder/approver

#### Option 2A — "Web-first" PWA (WebAuthn + PRF + direct Google calls)
| Dimension | Assessment |
|---|---|
| Reach | ✅ the 5 OSes through the browser, no store |
| Security at rest | 🟠 browser vault < native hardware vault; PRF extension still young |
| Cost | 🟢 the leanest |

**Rejected** given the PO's priority (maximum security at rest). Remains a candidate for a quick *prototype* if needed.

#### Option 2B — Tauri 2 (Rust) (chosen)
| Dimension | Assessment |
|---|---|
| Reach | ✅ desktop **and** mobile (Tauri 2) |
| Security at rest | ✅✅ native access to Secure Enclave / StrongBox / TPM; Rust core (memory safety) |
| Auditability (open source) | ✅✅ small binary, reduced surface (vs Electron) |
| Cost | 🟠 stack to set up; Tauri mobile ecosystem young but viable |

**Chosen**: best alignment of security at rest and open-source auditability.

#### Option 2C — Flutter (Dart)
| Dimension | Assessment |
|---|---|
| Reach | ✅ the 5 OSes |
| Security at rest | ✅ native vault plugins (biometrics, secure storage) |
| Mobile UI velocity | ✅✅ the best |
| Cost | 🟠 heavier runtime; security core in Dart |

**Credible alternative**: preferable if the priority shifts toward mobile UI richness rather than the auditability of a minimal Rust core.

#### Option 2D — Keep Python, port it to mobile (BeeWare/Kivy)
**Rejected**: the mobile Python ecosystem is immature for a security component with background tasks and a hardware vault.

### Axis 3 — Cross-OS biometric approval

**Passkeys / WebAuthn (chosen)** versus *rewriting a native biometric helper per OS*. The FIDO2 standard gives, through **one** API, an enclave-held key + biometrics + signing of a challenge — across the 5 OSes. Writing 5 native helpers (like `elicitation-sign.swift`) would be the same work five times over. The ADR-0005 logic (canonical payload, `nonce`, receipt) is **kept**; only the signing mechanism changes.

**Device-bound constraint (hardening).** The approver passkey must be **bound to the device** (platform authenticator, *not synced*) and guarded by **biometric verification** — a *synced passkey* (iCloud / Google Password Manager) or a simple PIN guarantees neither "this precise phone" nor the enclave, and ends up on other devices. Enrollment requires **user verification** and, where possible, **attestation**; *synced* or purely *software* authenticators are **refused** for this role.

## Threat model (new — the cloud agent changes the game)

ADR-0005 assumed a **semi-honest local** agent (able to bypass via bare `gws`, but physically nearby). As soon as the requester is **cloud**, it must be assumed **remote and potentially hostile**. Consequences, non-negotiable:

- The holder **never trusts** the requester: every sensitive action requires a fresh **signed approval** (anti-replay through `nonce` + `expires_at`).
- **WYSIWYS** is mandatory: the phone displays the action *before* the signature; we never sign something opaque.
- The relay (if any) is **blind**: it carries **end-to-end encrypted** envelopes in both directions (challenges/signatures **and** results), never decrypting any token or content. It is the **only return channel** when the holder is behind a NAT — the content read passes through it, but *encrypted*, unreadable to the relay.
- **Least authority** is kept: the approval covers *one* action (account, target, duration), not a blank check. The per-service default-deny policy and temporary Drive zones remain the reference.

## Link with per-session rights (ADR-0007 / PR #108)

A **parallel** axis (PR #108, ADR-0007 "per-session rights") isolates the scope of **each session** (conversation): `session_id` + a right token carried in the call + fine granularity, itself reusing signed elicitation (ADR-0005). The two axes **fit together**:

- this ADR's *requester* **is** a "session" in the sense of ADR-0007;
- the *approver* (passkey, phase 1 / backlog item 0078) **is** the "remote consent" of ADR-0007's **phases B/C** — to be designed **once**;
- order: the *session* layer is laid first (ADR-0007 phase A, desktop); mobile consent (this axis) plugs into it afterward.

The two ADRs remain **distinct** (different questions: *per-session isolation* vs *where / how to approve + hold*) but **must describe the same signed-consent mechanism** (ADR-0005 foundation).

## Consequences

**Becomes possible**
- Reach your Google accounts from mobile, Mac on **or off**, without ceding tokens to a third party.
- Approve from the phone through **one** standard API on the 5 OSes.
- **Hardware** security at rest (non-exportable key, guarded by biometrics).
- Distribute the project as **free software** without imposing central infrastructure.

**Becomes harder / costlier**
- The mobile holder **leaves Python**: core rebuild (Rust/Tauri). This is the hard point.
- **Two holder implementations** will coexist during the transition (existing Python-macOS + native) → risk of security-rule divergence, to be framed.
- **Multi-device OAuth**: the same Google account held by the Mac *and* the phone forces a choice between **per-device enrollment** (each device has its own tokens in its vault — recommended) and **encrypted synchronization** between devices (more convenient, larger surface).

**Settled on 2026-08-15 (see Decision §8)**: *per-device* enrollment; both holders coexist (gradual migration); license ~~Apache-2.0~~ → **MIT** (corrected on 2026-09-04, see §8).

**To revisit later (child ADRs/backlog items)**
- **Blind relay design** (protocol, discovery, hosting) — and the "Mac on" case without a relay (direct LAN / WireGuard-style tunnel). → child ADR.
- **Multi-device enrollment**: the *concrete protocol* (the "per-device" principle is settled in §8). → child ADR.
- **Desktop unification** on Tauri 2 in the long run (removing Python): open — decision deferred.
- **Public threat model** published + **multi-OS CI** (desktop + mobile builds; see GHA cost).

## Next steps (action items)

1. [x] Validate this ADR (direction + invariants) with the PO — **Accepted on 2026-08-15** (see §8).
2. [x] Open the **backlog item** — epic **0077** + phase 1 **0078**.
3. [ ] **Phase 1, low risk**: put **passkey** approval on the *current* architecture (Mac = holder on, phone = approver) — immediate benefit, no rebuild.
4. [ ] Native Tauri 2 holder **prototype**: seal a token in the hardware vault + one Google call, on a mobile OS.
5. [ ] A child ADR on **multi-device enrollment** and another on the **blind relay**.

## References

- [ADR-0005](ADR-0005-signed-elicitation-v2.md) — signed elicitation (signing component reused).
- **ADR-0007** "per-session rights" (PR #108) — complementary axis: per-session isolation; its remote consent (phases B/C) = phase 1 of this axis (backlog item 0078). Same signing foundation (ADR-0005).
- [ADR-0003](ADR-0003-drive-content-via-broker-deposit.md), [ADR-0006](ADR-0006-received-files-dedicated-directory.md) — content lanes, "default-deny" threat model.
- Current code: `gateway/mcp_server.py` (stdio), `gateway/broker_server.py` (4878), `gateway/elicitation.py`, `scripts/elicitation-sign.swift`, `admin/server.js` (4877).
- Standards: WebAuthn / FIDO2 (passkeys), hardware vaults (Secure Enclave, Android StrongBox/Keystore, TPM).
