# The policy model — who is allowed to do what

A **policy** is the list of what a connected account is allowed to do:
read its emails? prepare drafts? write to Drive, and where exactly?
The base rule is deliberately cautious — **what is not explicitly
allowed is denied** — and it is *you* who widens it, never the assistant.

Concretely, each account carries a small file
`~/.config/gws-accounts/<alias>/policy.json`, checked by
[`policy-check.py`](https://github.com/elzinko/google-mcp-multi-account/blob/main/scripts/policy-check.py)
**before every command** — whether you type `mag …` or the
assistant goes through the MCP. `mag add` writes a cautious one by default: a brand-new
account is therefore already restricted. For everyday use, see
[Everyday usage](usage.md).

## Default-deny, per service

**A service missing from the policy is denied** (except `auth` / `schema`,
local introspection) — including for reads. A service that is present is *fail
closed*: only a category explicitly set to `true` passes. `mag add` writes
a cautious policy automatically, so a fresh profile is restricted
from the start. Consequence: services the admin does not model (chat, meet,
people, slides, forms, script…) are denied by default — no action visible
from the outside escapes control.

- **Drive** — by zones: read everywhere, write only under the authorized
  folders (subfolders included — parents are walked up via the API). Legacy
  modes: `open`, `readonly`, `restricted`.
- **Gmail** — categories `read`, `drafts`, `send`, `labels`, `update`, `delete`,
  `settings`. The winning combo: *drafts without sending* — the LLM prepares, you send.
- **Calendar / Keep / other modeled services** — `read`, `create`, `update`,
  `delete`, `share`.

```bash
mag policy mw allow "LLM"        # Drive: PERMANENT zone under the "LLM" folder
mag policy mw show               # shows the profile's full policy
mag mw drive files create --json '{"name":"x"}'   # ✗ denied (no authorized parent)
mag mw gmail users messages send --json '…'       # ✗ denied if "send": false
mag policy mw clear              # Drive goes back to open (other services unchanged)
```

## Temporary zones — the Drive elicitation flow

By default a `zonesOnly` profile is allowed to write *nowhere*. When
an LLM wants to write somewhere, it runs into a refusal that tells it what to
ask for; it is **you** who grants, for a limited time (default 8 h,
automatic expiry — so it has to be asked again for each work session):

```bash
mag grant coloc "Compta 2026" 4   # write under this folder for 4 h
mag grants coloc                  # active temporary authorizations
mag grant coloc revoke <folderId> # revoke before expiry
```

Every refusal is logged and invites the LLM to *ask* for the widening —
elicitation, again. *Accepted limit: it is the wrapper that enforces, not
Google — the only 100% Google-side lock would be the `drive.file` scope.*

## Per-session rights — the fine grain (ADR-0007)

The policy and zones above are the **machine floor**. On top of that,
each **conversation** (LLM session) carries its **own** rights, signed and
time-limited — another conversation does not inherit them. This is the finest
grain: per **service × operation × resource**.

- The human opens a session (`mag session open`) — a **signed** gesture (Touch ID
  under strongauth) that returns a **token**; the assistant presents this token on
  every call (without a token: no access to data, only the creation
  request).
- Each capability grant is **signed** too — never a silent
  widening:

```bash
mag session open                                    # creates a signed session → token
mag session grant-capability <jeton> mw gmail read  # this session: Gmail read
mag session grant-capability <jeton> mw drive create "Compta 2026"  # zoned write
mag session list                                    # active sessions + their config
```

- **Effective rights = account policy ∩ project manifest ∩ session capabilities**
  (intersection, *fail closed*). Outside a git repo (no manifest), `policy ∩
  session`; but a **tampered** manifest closes everything (anti-downgrade).
- **Sub-agents** inherit a subset of the parent's rights (never more) and cannot
  widen them on their own; the parent revokes its whole descendance in one action.

Design details: [ADR-0007](adr/ADR-0007-per-session-rights.md).

Hardenings of this model that are already settled: see the backlog item
`features/done/0002-durcir-modele-policy-default-deny.md` (default-deny
verified and tested) and [threat-model.md](threat-model.md).
