# google-multi-account

**Multi-account Google Workspace for LLM agents — 100% local.**

Connect Claude Desktop, Claude Code or Cursor to *several* Google accounts through
a local [MCP](https://modelcontextprotocol.io) server. The agent can *request*
access; only you grant it — every unlock, every Drive zone, every new account
stays a **human action**.

<div class="grid cards" markdown>

- :material-rocket-launch: **[Get started](#installer)**
  Install without cloning, connect an account, ask the LLM.

- :material-shield-lock: **[Security first](threat-model.md)**
  Default-deny, per-profile locks, zoned Drive writes, zero mail sending.

- :material-tools: **[CLI (mag)](usage.md)**
  `mag`: profiles, locks, Drive zones, Touch ID.

- :material-sitemap: **[Under the hood](architecture.md)**
  MCP, gateway, loopback broker, wrapper — who talks to whom.

</div>

## What you get

- **Multi-account, not a single token** — each account is a *profile* with its own
  policy, locks and Drive zones. The agent targets an alias, never "your
  Google" as a whole.
- **The human holds every door** — unlock, Drive zone, new account,
  IAM fix: the agent *proposes the exact command* (elicitation), you run it.
- **Default-deny by design** — any undeclared service is refused; the
  Gmail tools stop at the draft (no sending); Drive writes stay
  inside the granted folders.
- **100% local** — encrypted tokens (AES-256-GCM, master key in the macOS
  Keychain), audit log per client. The only cloud step: one OAuth credential,
  once.

## Install { #installer }

**Prerequisites** — the upstream [`gws`](https://github.com/googleworkspace/cli) CLI (the
Google Workspace CLI this project wraps) and Python 3:

```bash
brew install googleworkspace-cli
```

Then, to **use** the server (no need to clone the repository):

```bash
curl -fsSL https://raw.githubusercontent.com/elzinko/google-mcp-multi-account/main/install.sh | bash
```

This downloads the latest version, puts it on your machine, wires up Claude
Desktop and Claude Code (Cursor: wire it by hand), and prints at the end
the remaining **Google setup** (one OAuth project, ~10 min — see
[OAuth / Google Cloud](setup-oauth.md)). No account connects until that is
done — but `setup_status` already runs to guide you.

Once the Google setup is done, connect an account, then restart Claude Desktop:

```bash
mag add perso votre.email@gmail.com   # "perso" = short name · the email pins the account
mag list             # profiles + state
```

Update later, **still without cloning**:

```bash
mag update
```

!!! tip "Cloning is for contributing"
    The git clone is only needed to develop the project. See
    [Install & update](mcp-setup.md) and [Contributing](PR_VALIDATION.md).

## Going further

| I want to… | Page |
|---|---|
| Wire up a client, see the exposed tools | [Install & update](mcp-setup.md) |
| Do the OAuth / Google Cloud setup, IAM roles | [OAuth / Google Cloud](setup-oauth.md) |
| Drive `mag` (profiles, locks, Drive zones) | [CLI (mag)](usage.md) |
| Drive the web admin (accounts, locks, policies) | [Web admin](admin.md) |
| Understand the policy model (default-deny, zones) | [Policy model](policies.md) |
| See the security guarantees, phase by phase | [Threat model](threat-model.md) |
| An honest look (strengths, limits, competition) | [Critique](critique.md) |

---

Open-source project ([MIT](https://github.com/elzinko/google-mcp-multi-account/blob/main/LICENSE)),
built in spare time. A security concern?
[SECURITY.md](https://github.com/elzinko/google-mcp-multi-account/blob/main/SECURITY.md).
