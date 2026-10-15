# Everyday usage

Usage details for `mag`, the "access on demand" lock, and strong
authentication. Web admin interface (separate page):
[admin.md](admin.md). Overview: [README](https://github.com/elzinko/google-mcp-multi-account/blob/main/README.md).
Policy model (who is allowed to do what): [policies.md](policies.md).

## On the command line (`mag`)

**Built-in help**: `mag help` lists the subcommands. Some nested dispatchers
detail their options with `--help` (e.g. `mag sandbox --help`).

The wrapper isolates each account via `GOOGLE_WORKSPACE_CLI_CONFIG_DIR`. You refer to
an account by its **email address** (the clearest way) and call
`mag <email> <gws command…>` (never a bare `gws`):

```bash
mag vous@gmail.com gmail users messages list --params '{"userId":"me","maxResults":5}'
mag vous@gmail.com drive files list --params '{"pageSize":10}'
mag vous@gmail.com calendar +agenda --today    # today's agenda
mag vous@gmail.com auth status                 # connection status
```

> **Alias = optional shortcut.** If the email is long to type, name the account
> when you connect it (`mag add perso vous@gmail.com`) and then use the short alias
> (`mag perso …`) wherever an email is accepted.

For data (Gmail/Drive), prefer the **MCP tools** (see
[mcp-setup.md](mcp-setup.md)). The `mag` shell remains for the human admin and
for cases the MCP does not cover.

## Connection on demand (elicitation)

A profile can be **locked**: it stays connected (connection in place) but
refuses every command until you explicitly unlock it —
an LLM that runs into the lock must ask you for access.

```bash
mag lock vous@gmail.com        # access on demand only
mag vous@gmail.com gmail …     # ✗ profile locked 🔒 → the LLM must ask
mag unlock vous@gmail.com 30   # unlocked for 30 min, automatic re-lock
```

[.claude/settings.json](https://github.com/elzinko/google-mcp-multi-account/blob/main/.claude/settings.json) adds a second barrier,
native to Claude Code: commands on sensitive profiles (and `mag unlock`)
trigger an explicit permission request.

Illustrated sequence: [diagrams/lecture-donnees-elicitee](https://github.com/elzinko/google-mcp-multi-account/tree/main/diagrams/lecture-donnees-elicitee/).

## Strong authentication (Touch ID) — optional

```bash
mag strongauth on      # unlock and grant will require Touch ID / Apple Watch
mag strongauth status  #   (or the macOS session password as a fallback)
mag strongauth off     # turn off (itself protected by Touch ID)
```

Once enabled, every profile unlock and every Drive zone authorization
triggers the system biometric dialog
([scripts/touchid.swift](https://github.com/elzinko/google-mcp-multi-account/blob/main/scripts/touchid.swift), Apple's LocalAuthentication
framework, 100% local). Elicitation approval can then only come from a human
physically present at the Mac — an LLM (or a script)
cannot simulate it. It also applies to `mag add` (connecting a
new account).

## From Claude Code

Open a session in this repo: the `.claude/skills/gws-*` skills and the
[CLAUDE.md](https://github.com/elzinko/google-mcp-multi-account/blob/main/CLAUDE.md) instructions are loaded automatically. Ask in
natural language, e.g. "list my 5 latest emails from the perso account".
