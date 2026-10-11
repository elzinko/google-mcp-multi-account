# Architecture decisions (ADR)

An **ADR** (*Architecture Decision Record*) is a **dated** design decision:
it explains *why* the project chose a given path, not only what it does. Each
record follows the same skeleton — **Context** (the problem, the
constraints) → **Decision** → **Options considered** (weighed, then rejected, with their
reasons) → **Consequences**.

**How to read them.** Each ADR is **self-contained**: open the one you care about and
start with its **TL;DR** (one sentence, at the top). One thread runs through all of them:
*the tool verifies, the human authorizes, the LLM proposes.* The recurring vocabulary is
defined in the **glossary** below — keep it open next to you while reading.


## Glossary

- **access_request** — the MCP elicitation tool: it **returns a command for the human to run**, it never executes anything.
- **admin** — the **local** web interface (`mag admin`, `127.0.0.1:4877`) where the human manages accounts; never exposed beyond loopback.
- **alias** — the short name of a profile (e.g. `perso`). Optional: in `mag` commands, you can also designate an account by its **email** (the MCP tools, for their part, use the alias).
- **broker** — the local daemon (`bin/google-broker`, `127.0.0.1:4878`) — the **only** one to run `gws` to **access data**; it re-checks lock and policy on every call (discovery, for its part, still reads `gws auth status` live).
- **session capability** — a fine-grained right granted to a **session**: (service × operation × resource?), **signed** and expiring. It intersects with the account policy and the project manifest; never a silent widening (ADR-0007).
- **client_secret.json** — the secret of the OAuth app ("Desktop app"), stored **outside the repository**. The MCP surfaces only check its **presence**; it is never displayed or committed.
- **connector** — the `google-multi-account` entry under `mcpServers` in the client config — not to be confused with the `google-mcp-multi-account` **repository**.
- **trash (Drive)** — moving to the trash counts as a **deletion** (`delete` category); the root of a zone is immutable (backlog item 0037).
- **default-deny** — the base rule: anything not explicitly allowed is **refused** (an undeclared service is refused).
- **capability descriptor** — the rights labels displayed in the admin, **derived in the browser** (`admin/index.html`) from the raw policy flags served by `/api/profiles` — never hard-coded (ADR-0004).
- **.downloads** — the folder (`~/.config/gws-accounts/.downloads`, 0700) where **received attachments** land — never an arbitrary path, never an overwrite (ADR-0006).
- **.email** — one file per profile that remembers the email, readable **even when the profile is locked** (for diagnostics). Gateway/MCP reads never re-run `gws`; only a human backfill (`mag list`, admin) can recompute it for an old profile (ADR-0002).
- **gateway** — `gateway/`: the layer that checks **lock + policy** before every call to Google.
- **mag** — the CLI **of this project** — the human control station (`add`, `lock`/`unlock`, `grant`, `policy`, `wire`). Formerly `mag` (deprecated alias kept).
- **grant** — a **temporary** authorization to write in a Drive zone, for the duration of a session (`.sessions/<id>.json`).
- **gws** — the official **Google Workspace** CLI (upstream, to be installed) that actually talks to the Google APIs.
- **IAM (Google Cloud role)** — the right, **per account**, to use the OAuth project (`serviceUsageConsumer`). Without it, a "connected" account fails on the first real call.
- **session token** — the secret created by `mag session open` (**signed** human action) that identifies a **session**; the assistant presents it on every call. Without a token: no data access, only the creation request (ADR-0007).
- **MCP** — the protocol (*Model Context Protocol*) through which the assistant talks to the local server.
- **policy** — the `policy.json` file of a profile: it says, service by service, what is allowed (read, send, create…).
- **profile** — a connected Google account, isolated in its folder `~/.config/gws-accounts/<alias>/`.
- **MCP server** — `bin/google-mcp`: the entry point to data (Gmail/Drive) for the assistant.
- **session** — an LLM conversation, identified by its **token** (not the MCP connection); it carries its own rights, **isolated** from other sessions, with a TTL / revocation lifecycle (never disconnection). Sub-agents inherit a subset of the parent's (ADR-0007).
- **setup_status** — the **diagnostic** MCP tool (read-only): it reports the state of the setup and **proposes** the commands for missing steps.
- **strongauth / Touch ID** — **optional** mode (`mag strongauth on`): once enabled, every unlock/grant/connection requires a **Touch ID** fingerprint that signs the exact action.
- **unlock** — unlock a profile, usually for a limited time (automatic re-lock).
- **.uploads** — the temporary folder from which `gws` **uploads** content to Drive, for the duration of one call (ADR-0003).
- **vault** — the **planned** isolation (Phase 2.1) that will put credentials out of an agent's reach — not yet built (backlog item 0003).
- **lock** — a **locked** profile refuses all data access until a human has unlocked it (`.locked` / `.unlock-until`).
- **zone (Drive)** — a Drive folder under which writing is allowed (`writeFolders`). Outside a zone: refused.
- **elicitation** — when the assistant cannot act itself: it **proposes** the exact command, and the human runs it (unlock, grant, connection). The LLM never widens its own access.
- **signed elicitation** — the hardening (ADR-0005): Touch ID consent is **cryptographically bound** to the exact action, not just "a human is present".
