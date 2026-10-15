# Getting started

This guide takes you from zero to your first exchange: *"Claude, summarize my
latest emails"* — across **several** Google accounts, **locally**, without ever
letting the assistant act on its own.

Allow **~15 minutes**, most of it for a Google step you only do once.

!!! info "What you need"
    - a **Mac** (Apple Silicon);
    - an MCP-compatible client: **Claude Desktop**, **Claude Code** or **Cursor**;
    - one or more **Google accounts** (`@gmail.com` or Workspace).

## In one sentence, how does it work?

A small server runs **on your machine**. Your assistant talks to it through the
[MCP](https://modelcontextprotocol.io) protocol; the server, in turn, talks to Google.
Between the two, one simple rule: **the assistant can *request* access, but you
are the one who opens it.** Nothing leaves your machine, no email goes out without your action.

## Step 0 — Install the Google tool (`gws`)

The project relies on the official **Google Workspace** CLI (`gws`). Install it
first, otherwise the "connect an account" step will fail:

```bash
brew install googleworkspace-cli
```

## Step 1 — Install the connector

One command, nothing to clone:

```bash
curl -fsSL https://raw.githubusercontent.com/elzinko/google-mcp-multi-account/main/install.sh | bash
```

You get the **`mag`** command in your terminal (that is *your* control
station: connect accounts, lock, authorize) and the server, ready to be
wired up. At the end, the installer prints what is left to do on the Google side.

## Step 2 — Create the Google project (once)

Google requires two manual actions in its console: creating an **OAuth credential**
and **publishing** the application. It is free, nothing is hosted — just an ID
card that authorizes `mag` to connect to *your* accounts.

The detailed step-by-step guide: **[OAuth / Google Cloud](setup-oauth.md)** (~10 min).
At the end, you have a `client_secret.json` file in place.

## Step 3 — Connect an account

Each account connects through the **browser** — you pick the account, Google
asks for your consent. No password passes through the tool.

```bash
mag add perso vous@gmail.com     # "perso" = a short name; the email identifies the account
```

Repeat for each account (`mag add asso vous@asso.org`, etc.). Check:

```bash
mag list                          # your accounts and their state
```

!!! tip "Email or alias?"
    Everywhere, you can refer to an account by its **email** (`mag lock
    vous@gmail.com`) — the clearest way. The short alias (`perso`) remains an
    optional **shortcut** if the email is long to type.

## Step 4 — Wire up your client

One command links the server to your assistant:

```bash
mag wire desktop      # Claude Desktop
mag wire code         # Claude Code (the "claude" CLI)
mag wire all          # both
```

Then **restart the client**. (For Cursor and per-client details, see [Connect an LLM client](connect-client.md).)

## Step 5 — First exchange

In your assistant, simply ask:

> "Give me an overview of my Google setup."

It reads the state and, for each gap, proposes the exact command to run.
Then try:

> "Summarize the last 5 emails of vous@gmail.com."

If it runs into a **lock** 🔒, that is normal: an account can be locked (access
on demand). The assistant then proposes the command — it is up to you to run it:

```bash
mag unlock vous@gmail.com 30      # unlocked for 30 min, automatic re-lock
```

That is the whole principle: **the assistant proposes, you decide.**

## What's next?

- **[Everyday use](usage.md)** — the `mag` CLI, Touch ID.
- **[Admin interface](admin.md)** — manage accounts, locks and policies from the browser.
- **[Policy model](policies.md)** — what each account is allowed to do (by default: read, drafts, zero sending).
- **[Security](threat-model.md)** — what the project guarantees, and what it does *not* guarantee.
- Trouble during install? **[Connect an LLM client](connect-client.md)** (manual config per client) and **[Install & update](mcp-setup.md)** (multiple versions, troubleshooting).
