# A critical look — strengths, limits, risks

This document is an **honest self-assessment** of the project, for a developer who
is evaluating it or wants to contribute. It says what the project does well, what it does
poorly, and what could make it useless. It complements [`SECURITY.md`](https://github.com/elzinko/google-mcp-multi-account/blob/main/SECURITY.md)
and [`threat-model.md`](threat-model.md) (security-focused) with a broader view:
product, engineering, strategy.

*Written on 2026-07-24, reviewed on 2026-08-08. The project moves fast: some limits
below are already fixed — the MCP tool count and the state of
installation (releases, `curl` without a clone) have been refreshed.*

## In one sentence

A **careful and honest** tool, today shaped for **a single user**
(its author, on macOS). Its security argument does **not** hold against an agent
that has a shell.

## What the project does well

- **It documents its own flaws.** The threat model describes the bypasses
  instead of hiding them — rare for a project.
- **The policy layer is real and tested.** Default-deny per service and per
  account has a hermetic test suite, with non-regression tests for real
  bypasses found in audit.
- **Per-account governance is rare.** "Access on demand" locks, temporary Drive
  grants, human elicitation: this combination is not found in any
  other known MCP server (see [Against the competition](#against-the-competition)).
- **It is small and has no heavy dependencies.** ~3,400 lines, pure stdlib (Python,
  bash, Node), nothing to install via npm or PyPI.

## The limits

### 1. Security mostly protects against a *cooperative* agent

The stated goal: the LLM cannot go beyond what we allow. In practice, a
single command bypasses policy, locks, and audit log all at once:

```bash
GOOGLE_WORKSPACE_CLI_CONFIG_DIR=~/.config/gws-accounts/<alias> gws …
```

A client **with a shell** (Claude Code, Cursor) can type it. The barrier therefore holds
only as long as the agent **is willing** to respect it — it is not a real lock.
The project documents this itself in [`threat-model.md`](threat-model.md).

Two honest nuances:

- For a client **without a shell** (Claude Desktop over stdio MCP), the barrier holds
  much better.
- The project recently moved data access through a **broker** (the
  gateway no longer calls `gws` directly). That is a good thing, but it does not close
  the bypass above: as long as credentials remain usable by
  `gws`, the command works. The real fix — moving credentials out of the
  agent's reach — is an identified workstream, **not done yet**.

### 2. Everything rests on a still-young third-party CLI (`gws`)

Multi-account comes from a detail of `gws`: the variable
`GOOGLE_WORKSPACE_CLI_CONFIG_DIR`. But `gws` is pre-1.0 ("expect breaking
changes"), and its text output is parsed with regular expressions in several
places. A single release can break the chain. No version is pinned.
Native multi-account was in fact removed from the CLI, then requested by its
users ([issue #293](https://github.com/googleworkspace/cli/issues/293)):
if it comes back, this wrapper becomes a trivial alias.

### 3. macOS only (for now)

Keychain (encryption key), Touch ID, `stat -f`, `open`: the production path
only works on Apple Silicon macOS. The README now flags this (macOS badge), and the install symlink uses `$(brew --prefix)`
instead of a hard-coded path. But making it truly portable (Linux, Intel)
is still to be done.

### 4. MCP coverage is narrow

17 MCP tools, 3 of them utilities. There is Gmail (read, draft, attachments) and
Drive (read, create, update, copy, upload, share). But Calendar, Docs,
Sheets, Tasks: **no** MCP tool — reachable only through the `mag` shell,
so **not from Claude Desktop**. By comparison,
[taylorwilsdon/google_workspace_mcp](https://github.com/taylorwilsdon/google_workspace_mcp)
exposes about a hundred tools across 12 services. This is the weakest point against
the competition.

### 5. Installation is costly

Each user must create their **own OAuth app** in the Google Cloud
console. The scopes used (full Drive, `gmail.modify`) are classified by Google as
**restricted**. Consequence:

- a shared app must go through a [restricted
  scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification)
  and a **CASA** security audit, to be redone **every year** (paid);
- otherwise, you stay in *Testing* mode: tokens **all expire after 7 days**.

This is Google's OAuth wall, not a code defect. But it caps adoption:
only a developer already comfortable with Google Cloud will get through this setup.

### 6. The project is built for one person

The production path is **macOS only**, and the defaults assume one person's personal
Google accounts. Installation, however, is no longer a barrier: `curl | bash` without a
clone, tagged versions and **GitHub releases**, update via `mag update`. What remains
is that no "one-click" format like [Desktop Extensions
`.mcpb`](https://www.anthropic.com/engineering/desktop-extensions) is produced yet,
and that the target audience stays narrow.

## Against the competition

| | This project | Open-source MCP servers | Managed connectors (claude.ai…) |
|---|---|---|---|
| Installation | heavy (personal OAuth app) | heavy (personal OAuth app) | **zero** |
| Services | 2 in MCP (Gmail, Drive) | **12** (e.g. taylorwilsdon) | a few |
| Multiple accounts | yes (local, by alias) | yes (multi-user OAuth 2.1) | **no** (1 account) |
| Fine-grained per-account control | **yes** (policy, locks, grants) | no | no |

Two honest nuances:

- The "multi-account" advantage sets this project apart **less** than it seems: the
  main open-source server
  ([taylorwilsdon](https://github.com/taylorwilsdon/google_workspace_mcp), several
  thousand stars) already handles several users.
- The project's **real** differentiator is therefore not multi-account, but
  **per-account governance** locally: default-deny, "access on demand" locks,
  temporary Drive grants, and human
  [elicitation](https://modelcontextprotocol.io/specification/draft/client/elicitation).
  No other known MCP server offers this at this granularity.

## What could make it obsolete

- **Official multi-account.** If `gws` adds `--account`, or if a claude.ai / Google
  connector handles several accounts, the core of the wrapper disappears (the README
  admits it).
- **Client permissions.** Claude Code can already limit tools
  (allowlists), sandbox the shell, and does elicitation natively. Part of the
  guardrails is therefore taken over on the client side.
- **What would survive:** the *design* (per-account governance, elicitation), not
  necessarily the code.

## External references

- Google Workspace CLI — multi-account request:
  [issue #293](https://github.com/googleworkspace/cli/issues/293)
- Competing MCP server:
  [taylorwilsdon/google_workspace_mcp](https://github.com/taylorwilsdon/google_workspace_mcp)
- MCP — elicitation (specification):
  [modelcontextprotocol.io](https://modelcontextprotocol.io/specification/draft/client/elicitation)
- Google — restricted scope verification & CASA audit:
  [developers.google.com](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification)
- Anthropic — Desktop Extensions `.mcpb`:
  [anthropic.com](https://www.anthropic.com/engineering/desktop-extensions) ·
  [modelcontextprotocol/mcpb](https://github.com/modelcontextprotocol/mcpb)

## See also

- [`threat-model.md`](threat-model.md) — the detailed threat model (security).
- [`../SECURITY.md`](https://github.com/elzinko/google-mcp-multi-account/blob/main/SECURITY.md) — guarantees, what is not guaranteed, reporting.
