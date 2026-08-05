<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="site/assets/readme-hero-dark.svg">
  <img src="site/assets/readme-hero.svg" alt="google-multi-account — Multi-account Google Workspace for agents" width="840">
</picture>

<br>

[![CI](https://github.com/elzinko/google-mcp-multi-account/actions/workflows/ci.yml/badge.svg)](https://github.com/elzinko/google-mcp-multi-account/actions/workflows/ci.yml) &nbsp;[![Release](https://img.shields.io/github/v/release/elzinko/google-mcp-multi-account?color=0f6e56)](https://github.com/elzinko/google-mcp-multi-account/releases) &nbsp;[![License](https://img.shields.io/github/license/elzinko/google-mcp-multi-account?color=1f6feb)](LICENSE) &nbsp;[![Platform](https://img.shields.io/badge/platform-macOS-1a1a1a?logo=apple&logoColor=white)](#-contributing)

**[Quickstart](#-quickstart)** · **[Permissions](#-permissions)** · **[Security](#-security)** · **[Docs](docs/)**

</div>

**Multi-account Google Workspace for LLM agents — 100 % local.** Connect Claude Desktop, Claude Code or Cursor to *several* Google accounts through a local [MCP](https://modelcontextprotocol.io) server. The agent can *ask* for access; only you grant it — every unlock, Drive grant and new account stays a human gesture.

---

## ✨ What you get

- **Multi-account, not one token** — each account is a *profile* with its own policy, locks and Drive zones. The agent targets an alias, never “your Google” as a whole.
- **The human holds every door** — unlock, Drive grant, new account, IAM fix: the agent *proposes the exact command* (elicitation), you run it.
- **Default-deny by design** — any undeclared service is refused; Gmail tools stop at the draft (no sending); Drive writes stay inside granted folders.
- **100 % local** — encrypted tokens (AES-256-GCM, master key in the macOS Keychain), per-client audit log. The only cloud step is a one-shot OAuth credential.
- **Scope today** — **Gmail + Drive** through MCP; **Calendar next**. Docs, Sheets and Tasks are reachable through the `gwsa` CLI.

## 👤 Who it's for

| You are… | You get… |
|---|---|
| **Juggling personal + work Gmail/Drive** | one agent that targets each account by alias — `perso`, `work`, a client — never “your Google” as a whole |
| **Letting an agent touch Drive, cautiously** | reads by default, *drafts* mail (never sends), writes only in folders you hand over — revocable and time-boxed |
| **Privacy-first** | tokens encrypted on your Mac (Keychain), a per-client audit log, no third-party server — the only cloud step is your own OAuth credential |

## 🚀 Quickstart

macOS Apple Silicon. **Install without cloning:**

```bash
curl -fsSL https://raw.githubusercontent.com/elzinko/google-mcp-multi-account/main/install.sh | bash
```

This installs the latest release, puts `gwsa` on your PATH, wires your Claude clients, and prints the one-shot **Google setup** that remains (an OAuth project, ~10 min — see [docs/setup-oauth.md](docs/setup-oauth.md)). Then connect an account and restart Claude Desktop (Cmd-Q):

```bash
gwsa add personal     # "personal" = your alias · browser → pick account → accept
gwsa list             # profiles + state
```

Ask the agent: *“give me a rundown of my Google setup”* — it reads the state and proposes the exact command for each missing step; you run them. Update later, still clone-free: **`gwsa update`**. Full detail: [docs/mcp-setup.md](docs/mcp-setup.md) · [docs/setup-oauth.md](docs/setup-oauth.md).

## 🔑 Permissions

**Default-deny**: anything not granted is refused. The agent can *request* a door; only you open it — this is the *elicitation* model.

| Door | Who opens it | How |
|---|---|---|
| **Unlock an account** (temporary access) | you | the lock in the admin, or `gwsa unlock <alias> <min>` |
| **Grant a Drive zone** (a folder to write in) | you | admin → *Configurer*, or `gwsa grant <alias> <folder> <hours>` |
| **Connect a new account** | you | `gwsa add <alias>` (browser OAuth) |
| **Fix project access** (IAM) | you | admin → *Réparer l’accès*, or the `gcloud` line the agent prints |
| **Send mail** | nobody, by design | Gmail tools stop at the draft |

Every request lands in the **audit log** (`GWSA_CLIENT` = which client asked), allowed or refused. Model in depth: [docs/policies.md](docs/policies.md) · [docs/usage.md](docs/usage.md).

## 🔒 Security

Stance: **don’t trust the LLM by default** — it can *ask*, only a human opens. Per-profile locks (optional Touch ID), zoned Drive writes, no mail sending, encrypted tokens. Guarantees phase by phase, what is *not* yet covered, and how to report a flaw: [SECURITY.md](SECURITY.md) · [docs/threat-model.md](docs/threat-model.md). Honest self-critique (strengths, limits, competition): [docs/critique.md](docs/critique.md).

## 🤝 Contributing

From a clone (contributors — end users install with the `curl` line above, no clone):

```bash
git clone https://github.com/elzinko/google-mcp-multi-account.git
cd google-mcp-multi-account
./scripts/test.sh     # hermetic suite (policy, wrapper, gateway, broker) — no real account, no network
```

- **Backlog** — one card per feature/bug in [features/](features/); **one PR per card**, [conventional commits](https://www.conventionalcommits.org/), merge on green.
- **Commands** — `gwsa help` is the index of everything. LLM-guided manual tests: [tests/manuels/](tests/manuels/).
- **Releases** — the git **tag** is the source of truth; `./scripts/release.sh` derives semver from the commits, tags, and publishes. History: [CHANGELOG.md](CHANGELOG.md).

### Project structure

```
bin/       # google-mcp (MCP server) · gwsa (CLI wrapper) · google-broker
gateway/   # policy, locks, MCP server, signed elicitation
scripts/   # provision-gcp · update · release · test
docs/      # setup, usage, policies, architecture, security, critique
site/      # product landing + docs hub (English, FR/EN toggle)
features/  # backlog — one card per feature/bug
```

<details>
<summary><b>Naming</b> — product vs repo vs CLI</summary>

Product / MCP server `google-multi-account` (source of truth: `gateway/config.py` `PRODUCT_SLUG`) · git repo `google-mcp-multi-account` · CLI `gwsa` · MCP binary `google-mcp`.
</details>

## 📚 Further reading

| Topic | Where |
|---|---|
| How it works — wrapper, local broker, security controls | [docs/architecture.md](docs/architecture.md) |
| Connect a client (Desktop, Code, Cursor); tools exposed | [docs/mcp-setup.md](docs/mcp-setup.md) |
| OAuth / GCP setup, IAM roles | [docs/setup-oauth.md](docs/setup-oauth.md) |
| CLI & web admin (`gwsa`, locks, Touch ID) | [docs/usage.md](docs/usage.md) |
| Policy model (default-deny, Drive zones, grants) | [docs/policies.md](docs/policies.md) |

## License

[MIT](LICENSE) — built in spare time. If it helps you, [buy me a coffee ☕](https://buymeacoffee.com/elzinko).
