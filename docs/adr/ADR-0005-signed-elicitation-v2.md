# ADR-0005 — Signed elicitation v2 (backlog item 0001)

**Date**: 2026-07-28  
**Status**: accepted (local mag implementation; second consumer whatsapp-group-mcp#0007 not required for the macOS path)

> **TL;DR** — **When strongauth mode is enabled** (`mag strongauth on`), every sensitive action (unlocking access, opening a shared folder, approving a project) must be validated by a Touch ID fingerprint that **cryptographically signs** the description of that exact action — instead of the old check that only verified a human was present — so that an approval can neither be replayed nor used to authorize a different action.

## Context

`mag strongauth` v1 = presence check (`touchid.swift`). Backlog item 0001 requires consent **cryptographically bound** to the action (unlock, grant, project manifest).

## Decision

1. **Single canonical payload** (`gateway/elicitation.py`): `action`, `alias`,
   `target`, `session_id`, `minutes`/`hours`, `nonce`, `issued_at`, `expires_at`.
   The Swift helper derives the Touch ID prompt **and** signs the canonical JSON
   (SHA-256 + ECDSA P-256).
2. **Key**: the `mag elicitation enroll` enrollment tries in order Secure Enclave
   → software Keychain → **file** `~/.config/gws-accounts/.elicitation/private.p256`
   (0600) + `public.der`. The file fallback is required because an unsigned `swift script.swift`
   often receives `errSecMissingEntitlement` (-34018) when creating a
   permanent Keychain/SE key. The public key stays outside the repo (dir mode 700).
3. **Receipts**: `~/.config/gws-accounts/.elicitation/receipts.jsonl` + entries
   `decision=elicitation` in `usage.jsonl`. Anti-replay: `nonces.json`.
4. **CI / Linux tests**: `GWSA_ELICITATION_MOCK=1` + `mag elicitation enroll --mock`
   (HMAC-SHA256, no Swift).
5. **Sharing**: local copy in this repo for now; extraction into a shared
   building block when whatsapp-group-mcp#0007 is delivered and both real
   uses are validated (no over-abstraction before then).

## Fallback (fail closed)

- `strongauth on` without enrollment → refusal with the message `mag elicitation enroll`.
- Biometrics unavailable (helper exit 2) → refusal, never a silent approval.
- No fallback to the plain presence check when strongauth is enabled.
- File mode: Touch ID (`LAContext`) **before** each signature; the receipt stays
  bound to the payload (ECDSA). The file private key is readable by the same UID
  (same threat class as the current vault — backlog item 0001 § gap no. 2).

## Limits (unchanged)

- Bypass via bare `gws` / filesystem editing: orthogonal (backlog item 0001 § gap no. 2).
- Verification happens at the time of the human `mag` command; the broker trusts
  the session registry once the human has passed.
- Unsigned helper: no "hard" SE until we ship a binary
  signed with Keychain entitlements (possible evolution).

## References

- `scripts/elicitation-sign.swift`, `gateway/elicitation.py`, `bin/mag`
- Backlog item 0001, whatsapp-group-mcp#0007 (mirror design, non-blocking for this path)
