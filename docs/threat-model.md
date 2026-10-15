# Security — the threat model

This page says **honestly** what the project protects, and what it does *not*
protect. No marketing promises: a tool that touches your emails deserves to be
clear about this. Component details are in [the architecture](architecture.md).

## In plain terms, first

The goal: let an AI assistant access **several Google accounts**, locally,
**without trusting it by default**. What that guarantees — and what it does not
guarantee:

- ✅ **Protected.** A *cooperative* assistant (one that goes through the tool) cannot
  send an email, write outside the folders you have opened, touch a locked
  account, or grant itself access. A new account is read + drafts,
  **zero sending**.
- ⚠️ **Not protected.** An assistant with a **free shell** on your machine can
  bypass all of this by calling the Google tool directly (detailed below, under
  "what is *not* guaranteed"). Elicitation disciplines *behavior*; it
  does not remove the *capability* as long as credentials are readable on disk.
  The countermeasure: restrict the agent's shell (see the mitigation); the vault that
  closes this gap is planned (Phase 2.1).

**In short: very solid against a cooperative agent, but not a prison against an
adversarial agent with disk access.** The rest of the page details each guarantee,
phase by phase.

## Trust surfaces

| Component | Role | Trust |
|-----------|------|-------|
| Human | unlock, grant, policy, OAuth | Root of trust |
| Admin `127.0.0.1:4877` | Cockpit | Local process; no app auth |
| `bin/mag` + `scripts/policy-check.py` | CLI guardrails | Applied if you go through them |
| `gateway/` + `bin/google-mcp` | MCP entry point | Same policy/lock; curated tools (no send) |
| `gws` + `~/.config/gws-accounts/` | Tokens + Google calls | **Real capability** to access data |

## Phase 1 (current) — what is guaranteed

- Profile created via `mag add` → **cautious policy** (Drive zones empty, Gmail without sending, unlisted services denied).
- Service missing from `policy.json` → **default-deny** (except `auth` / `schema`).
- Locked profile → refused via `mag` **and** via MCP.
- MCP tools: Gmail read + drafts + attachment (→ `.downloads`), Drive read (metadata + content) + create/copy/upload + **update** (content replacement, non-native files only) **under zones**; **sharing** read/write (`drive_permissions_create/list/delete`) — never **public** sharing (`type` fixed to `user`); **no** Gmail sending, permanent deletion, or **ownership transfer** (removed — dedicated PR not ready).
- ⚠ **Sharing** (`drive_permissions_*`) is only guarded by the `drive.share:true` policy (a **persistent** flag), **not** by zones or by a session grant: once `share` is enabled, the agent can share any file it owns to any email (never public — `type=user`). **Hardening to be decided** (security review F2): a session grant to share.
- `access_request` proposes unlock/grant **without running them**.
- Touch ID (`mag strongauth`): physical presence for unlock/grant (absolute paths `/usr/bin/swift` + `/usr/bin/swiftc` + repo scripts — never via PATH).
- **Per-session rights** ([ADR-0007](https://github.com/elzinko/google-mcp-multi-account/blob/main/docs/adr/ADR-0007-per-session-rights.md)): each conversation carries a signed **token**; its capabilities (service × operation × resource) are **isolated** from other sessions and **signed at each grant**; effective rights = policy ∩ project manifest ∩ session capabilities; a **tampered** project manifest closes everything (anti-downgrade). TTL / revocation lifecycle (an MCP disconnect purges nothing). Remains **cooperative** until the vault is in place.

## Phase 1 — what is **not** guaranteed

An agent with a **free shell** and filesystem access can still run:

```bash
GOOGLE_WORKSPACE_CLI_CONFIG_DIR=~/.config/gws-accounts/<alias> gws …
```

and bypass lock, policy, audit log, and MCP. Elicitation controls **cooperative
behavior**; it does not remove the **capability** as long as the credentials are
usable by `gws` outside the gateway.

**Recommended mitigation** (clients with a shell: Claude Code, Cursor Agent):

- Supported path for Google data = **MCP only** (`bin/google-mcp`).
- Restrict / deny in bash permissions: `gws`, `GOOGLE_WORKSPACE_CLI_CONFIG_DIR=…`,
  read/write of `~/.config/gws-accounts/`.
- Do not put `gws` in the agent's PATH if possible; the human keeps `mag` for admin.

## Phase 2 A (current) — loopback broker

- MCP → gateway → **broker** (`127.0.0.1:4878`, token `~/.config/gws-accounts/.broker-token`) → `gws`.
- The broker auto-starts on the first MCP tool call if needed (`bin/google-broker`).
- The broker re-applies lock + policy before `gws`.

## Phase 2 A — what is **not yet** guaranteed

Credentials remain in `~/.config/gws-accounts/`. An agent with a free shell
can still call `gws` directly. Mitigation: restrict the shell;
next step = vault (`features/0003-vault-credentials-hors-perimetre-agent.md`).

## Email = identity metadata (outside the lock)

A profile's email stays readable even when locked — it is the **only**
metadata exposed (IAM diagnostic of `setup_status`, SECURITY.md). Since
[ADR-0002](adr/ADR-0002-email-metadata-outside-lock.md), it comes from an
`.email` file written by the human `mag add` gesture (backfill: `mag list`,
admin) — **never** from a `gws` execution. Tested invariant: lock ⇒ zero
gws execution; no `GOOGLE_WORKSPACE_CLI_CONFIG_DIR` in `gateway/`
outside `broker_server.py`.

## Content deposited on Drive (deposit directory)

`drive_create(content=…)` materializes the text in
`~/.config/gws-accounts/.uploads/` (0700) for the duration of one `gws --upload` call:
this is the only way to pass media to `gws`, which otherwise refuses any
path outside its working directory ([ADR-0003](adr/ADR-0003-drive-content-via-broker-deposit.md)).
File in 0600, deleted in `finally` (on success and on failure) — exposure
comparable to `usage.jsonl`, which already logs command arguments.
Favorable side effect: `gws` now runs **from this directory**,
so its file sandbox is no longer the git repo. Drive zones
apply unchanged: `parents` stays in `--json`, the only place
`policy-check.py` reads to validate the destination.

## Received files (download directory)

`gmail_attachment_get` materializes an attachment — **third-party content**,
potentially hostile — in `~/.config/gws-accounts/.downloads/` (0700),
the only possible destination ([ADR-0006](adr/ADR-0006-received-files-dedicated-directory.md)).
The tool accepts **no destination path**: only an indicative `filename`,
reduced to a sanitized base name (never a separator, never hidden,
never empty). Written with `O_CREAT|O_EXCL` (0600), numeric suffix if the name
already exists — **never overwriting**. Symmetry with the upload direction:
`drive_upload` refuses to read under `GWSA_ROOT` (tokens, credentials, policies),
except for `.downloads` (re-uploading a received attachment). The final path is
returned to the caller, who then decides on a possible `cp` — outside the gateway.

On the upload side, the **source** of `drive_upload` is restricted to an **allowlist**
(`.downloads` + the folders declared in `<GWSA_ROOT>/.upload-roots`
or `GWSA_UPLOAD_ROOTS`), not the whole disk: the LLM cannot read an arbitrary
path (e.g. `~/.ssh/id_rsa`) and exfiltrate it to an active zone —
default-deny, only the human opens the readable folders (the `.upload-roots` file
is not writable by a tool) —
[ADR-0006](adr/ADR-0006-received-files-dedicated-directory.md).

## Phase 2.1 (planned) — vault

Credentials out of the agent's read reach; only the broker socket remains useful.

## Phase 1 — legacy profiles

A profile **without** `policy.json` (created before this hardening) stays unfiltered
by the checker until you set one. To switch: "cautious" preset
in the admin, or copy `gateway/default_policy.py`.

## Audit log

`~/.config/gws-accounts/usage.jsonl` — allowed calls (`decision:ok`), policy
refusals and lock refusals (`decision:refus`, `reason:locked`), on all three
paths (`mag`, broker, gateway fail-fast). `client` field via `GWSA_CLIENT`
(`mcp`, `claude-code`, `cli`, …). **Successful** calls additionally carry the
`session_id` and the service / operation / resource (per-session attribution).
Spoofable (`GWSA_CLIENT`): useful for debugging, not a strong identity.
