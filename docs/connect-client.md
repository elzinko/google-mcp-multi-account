# Connect an LLM client

Once the server is [installed](mcp-setup.md), a **single command** links it to your
assistant, from anywhere (`mag` is on the PATH):

```bash
mag wire desktop      # Claude Desktop
mag wire code         # Claude Code (the "claude" CLI)
mag wire all          # both — "--print" for a dry run
```

`mag wire` resolves the absolute path, **merges** the `google-multi-account` entry without
overwriting your other MCP servers, and makes a backup. Then **restart the client**.

!!! info "The installer wires nothing by default"
    `install.sh` **touches no client config**: it sets up the server then **prints**
    these commands — up to you to run them ("you hold every door" doctrine). To wire
    everything during the install: `curl … | bash -s -- --wire` (or `MAG_WIRE=1`).

!!! note "Why two names?"
    The **repository** is called `google-mcp-multi-account`, but the **connector** declared
    under `mcpServers` is called `google-multi-account` (without `mcp`) — MCP convention,
    like `github-mcp-server` → `github`. Details:
    [architecture](architecture.md#noms-depot-connecteur).

## Per-client details

=== "Claude Desktop"

    **Recommended** — one command:

    ```bash
    mag wire desktop           # wires (or updates)
    mag wire desktop --print   # dry run: shows without writing
    ```

    **By hand** — edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

    ```json
    {
      "mcpServers": {
        "google-multi-account": {
          "command": "~/.local/share/google-mcp/current/bin/google-mcp",
          "env": { "MAG_CLIENT": "claude-desktop" }
        }
      }
    }
    ```

    Path = the `curl` install above. If the app does not expand `~`, use the absolute path
    (`/Users/<you>/.local/share/…`); from a **clone**, point to `…/google-mcp-multi-account/bin/google-mcp`.
    Then **restart Claude Desktop**.

=== "Claude Code"

    **Claude Code has its own MCP config** (`~/.claude.json`), separate from Claude
    Desktop: wiring Desktop does **not** make it visible in the `claude` CLI.

    **Recommended**:

    ```bash
    mag wire code
    ```

    Under the hood, this delegates to the official CLI (`user` scope = visible everywhere):

    ```bash
    claude mcp add google-multi-account --scope user \
      --env MAG_CLIENT=claude-code --env MAG_BROKER_PORT=4878 \
      -- ~/.local/share/google-mcp/current/bin/google-mcp
    ```

    Verify: `claude mcp get google-multi-account`, or `/mcp` in a new `claude`.

=== "Cursor"

    No `mag wire cursor` yet (tracked by backlog item 0074) — manual config is
    therefore the **only** way. In the MCP settings (UI or `~/.cursor/mcp.json`), the
    `command` points to the binary **installed** by `curl`:

    ```json
    {
      "mcpServers": {
        "google-multi-account": {
          "command": "~/.local/share/google-mcp/current/bin/google-mcp",
          "env": { "MAG_CLIENT": "cursor" }
        }
      }
    }
    ```

    Cursor does not always expand `~`: if the server does not start, use the **absolute**
    path (`/Users/<you>/.local/share/google-mcp/current/bin/google-mcp`).
    From a **clone** (contributors), point to `…/google-mcp-multi-account/bin/google-mcp` instead.

## Variable names (`MAG_`, formerly `GWSA_`)

**In plain terms:** environment variables start with **`MAG_`** today.
The old **`GWSA_`** names still work — the server reads them as a fallback.
You have **nothing to change** in a config that is running. If both are set,
`MAG_` wins.

A client config only needs two variables:

| Variable (current) | Old name (fallback) | Role |
|---|---|---|
| `MAG_CLIENT` | `GWSA_CLIENT` | Client label in the audit log (`claude-desktop`, `claude-code`, `cursor`) |
| `MAG_BROKER_PORT` | `GWSA_BROKER_PORT` | Broker port (the "lane") — `4878` by default |
| `MAG_ROOT` | `GWSA_ROOT` | Config and accounts directory — advanced use, rarely set by hand |

`mag wire` and the installers now write `MAG_`. An existing entry still
using `GWSA_` is **migrated** to `MAG_` on the next `mag wire` (a backup is made
beforehand). The accounts directory (`~/.config/gws-accounts`) does **not** change name:
only the variables are renamed.

## Remove an entry

- **Claude Code**: `claude mcp remove google-multi-account`.
- **Desktop / Cursor**: remove the `google-multi-account` entry from the client's JSON
  config (the admin deliberately protects the stable entry — no accidental deletion).

!!! info "Under the hood"
    `mag wire` calls `scripts/install-claude-desktop.sh` / `install-claude-code.sh`
    (idempotent, with backup). You normally don't need to run them by hand — they
    remain for special cases (custom name/port, multiple versions:
    see [Install & update](mcp-setup.md)).
