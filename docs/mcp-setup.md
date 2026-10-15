# Install & update the MCP server

The [`bin/google-mcp`](https://github.com/elzinko/google-mcp-multi-account/blob/main/bin/google-mcp) binary exposes an MCP **stdio** server
(JSON-RPC, one line = one message). It talks to Google only through the
[gateway](https://github.com/elzinko/google-mcp-multi-account/tree/main/gateway/) (policy + locks + v1 executor → `gws`).

Prerequisites: the [`gws`](https://github.com/googleworkspace/cli) CLI installed
(`brew install googleworkspace-cli`) and Python 3. (No need to have connected
an account already: the `setup_status` tool guides initialization from the LLM client.)

## Install without cloning (curl)

To **use** the server (not develop it), there is no need to clone the repository:

```bash
curl -fsSL https://raw.githubusercontent.com/elzinko/google-mcp-multi-account/main/install.sh | bash
```

This downloads the latest published version, pins it in
`~/.local/share/google-mcp/` and puts `mag` on the PATH. **No LLM client is
wired by default**: the install prints the action (`mag wire …`, see [below](#brancher-un-client-llm));
add `--wire` (or `GWSA_WIRE=1`) to wire during the install.
What remains is the Google setup (OAuth/GCP), a **prerequisite** printed at the end — see
[Prerequisite — OAuth / Google Cloud](setup-oauth.md).

Update later, **still without cloning**:

```bash
mag update            # latest published version · --to v0.1.0 to roll back
```

`mag update` reads the latest version on GitHub and switches `current` to it. The
git clone is only needed to **contribute** (backlog item 0020).

## Connect an LLM client { #brancher-un-client-llm }

Once installed, link your assistant with one command:

```bash
mag wire desktop      # Claude Desktop
mag wire code         # Claude Code (the "claude" CLI)
mag wire all          # both — "--print" for a dry run
```

Per-client details (Claude Desktop, Claude Code, **Cursor**), manual config and
removing an entry → **[Connect an LLM client](connect-client.md)**.

## Exposed tools, by group

| Group | Tool | What it does |
|---|---|---|
| Discovery | `profiles_list` | Lists the profiles (alias, email, lock, policy) — always start here |
| Diagnostics | `setup_status` | Setup state (project, publication, IAM per account) + `next_actions`: commands to propose to complete/repair (read-only). Guides onboarding, even without a shell (Desktop) |
| Gmail — read | `gmail_list` · `gmail_get` | Searches then reads an account's messages |
| Gmail — attachment | `gmail_attachment_get` | Downloads an attachment into the dedicated local `.downloads` directory — never an arbitrary path, never overwriting ([ADR-0006](adr/ADR-0006-received-files-dedicated-directory.md)) |
| Gmail — draft | `gmail_draft_create` | Prepares a draft; **no tool sends mail** |
| Drive — read | `drive_list` · `drive_get` · `drive_read` | Lists / inspects files and folders (`webViewLink` included) and **who owns them** (`owner`, `owned_by_me`); `drive_read` reads the **content** as text (Doc → markdown, Sheet → CSV, text files as-is — not binaries) |
| Drive — zoned write | `drive_create` · `drive_update` · `drive_copy` · `drive_upload` | Under an authorized parent (zone policy + grants): creates / **modifies**, natively **copies**, or **uploads** a local file ([ADR-0003](adr/ADR-0003-drive-content-via-broker-deposit.md)) |
| Drive — sharing | `drive_permissions_list` · `drive_permissions_create` · `drive_permissions_delete` | Lists, grants (reader/commenter/writer) or revokes shares (policy `share:true` required); **ownership transfer out of scope** (dedicated PR not ready) |
| Elicitation | `access_request` | kind=`unlock` \| `grant` \| `add_account`: returns **the command for the human to run** — never executes anything |

**Admin policy ≠ MCP surface.** Ticking a box in the admin authorizes the matching
API methods through `mag`; the MCP exposes a subset of them.
Since backlog item `features/done/0043-lire-copier-televerser-drive-et-pj-gmail.md`
and this batch (update + sharing), content reading, copying, uploading,
modifying and sharing are in. **Ownership transfer** is out of scope
(dedicated PR not ready). Calendar / Keep may still appear in the policy without an
MCP tool (broader coverage: backlog item
`features/0021-couverture-mcp-elargie.md`). And by design, **no
tool** sends mail, deletes, or transfers ownership.

Every call goes through the gateway (lock + default-deny policy) then the
loopback broker, and everything is logged (`GWSA_CLIENT`). A refusal is
never a dead end: it carries the elicitation to propose — see the
[sequence diagrams](https://github.com/elzinko/google-mcp-multi-account/tree/main/diagrams/) (reading, account connection,
IAM repair).

## Manual smoke test (no client)

```bash
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  | ./bin/google-mcp
```

## Develop without breaking the MCP you use

By default, the server wired into Claude Desktop runs **the clone**, live.
Changing the code therefore changes the tool while you are using it — and
unvalidated code keeps access to the real accounts. To separate the two:

**1 · Publish a version** — the number is computed automatically:

```bash
./scripts/release.sh
```

The level comes from conventional commits since the last tag: a `feat` →
minor, a `BREAKING CHANGE` (or `type!:`) → major, otherwise patch. Pass
`patch`, `minor` or `major` to force, `--print` to see without writing anything.

The script refuses to publish in the dark: dirty tree, branch other than
`main`, behind `origin/main`, tag already set, no commit since the
last version, or red tests. When green it writes `CHANGELOG.md`, commits,
sets an annotated tag and pushes both.

**2 · Install that version on this machine** — one command, like a product:

```bash
./scripts/update.sh
```

It takes the latest published version, installs it next to the old one in
`~/.local/share/google-mcp/<tag>/`, switches `current`, recycles the broker, and
only touches the Claude Desktop config if the entry is missing or points
elsewhere. Rerun with nothing new, it says "already up to date" and stops.

| Option | Effect |
|---|---|
| `--check` | says installed / available, writes nothing |
| `--to v0.1.0` | installs a specific version (rollback) |
| `--force` | reinstalls even if it is already the current version |

One manual action remains, unavoidable: **restart Claude Desktop**. The
MCP server is launched by the application, it does not reload by itself.

Both commands are also `mag` verbs, and `mag` is on your PATH:
`mag update` and `mag release`. From the installed copy, `mag release`
finds the source clone on its own (`.source` file).

For special cases, the building blocks remain available:
`deploy-local.sh --tag v0.1.0` installs a version without going through `update`,
and `install-claude-desktop.sh` wires an entry by hand.

**3 · Work in the clone**, in its own lane:

| | Stable (in service) | Development |
|---|---|---|
| Code | `~/.local/share/google-mcp/current/` | your clone |
| `GWSA_ROOT` | `~/.config/gws-accounts` | `~/.config/gws-accounts-dev` |
| `GWSA_BROKER_PORT` | `4878` (default) | `4880` |

```bash
export GWSA_ROOT="$HOME/.config/gws-accounts-dev" GWSA_BROKER_PORT=4880
```

(4879 is reserved for the test suite — hence 4880 for development.)

**The distinct port is not cosmetic**: the broker does not restart if one
already exists and responds. Without separate ports, the first one started runs *everything*,
for both lanes — you would think you are testing your changes while you are
running the old code.

Check which is which: the server announces its version in `initialize`. The deployed
copy announces its tag, the clone announces `dev`.

```bash
./scripts/deploy-local.sh --list        # deployed versions (* = current)
./scripts/deploy-local.sh --rollback v0.1.0
mag broker status                      # on the current lane
```

`mag broker status|stop` only drives the broker of **its own** port: the pidfile
is named `.broker-<port>.pid`, the token `.broker-<port>-token`.

## Wire two versions at the same time

Useful to try a version without losing the one that works. Each entry needs
its own name **and** its own port:

```bash
~/.local/share/google-mcp/v0.1.0/scripts/install-claude-desktop.sh \
  --name google-multi-account-v0.1.0 --port 4881
```

For a throwaway **branch / PR** (without touching `current` or the stable
`google-multi-account` entry @ 4878): `mag sandbox deploy --wire` (or
`mag sandbox wire` afterwards). Selective unwire:
`mag sandbox wire --remove desktop` (directory kept);
nuclear option: `mag sandbox remove <id>`. Details: `mag sandbox --help` and backlog item
`features/0046-sandbox-deploy-cli.md`.

Three rules, otherwise the entry name lies about which version answers:

- **One port per entry.** The installer writes `GWSA_BROKER_PORT` into the config,
  and refuses two different binaries on the same port.
- **Target the version directory, never `current`.** `current` follows the symlink:
  an entry pinned to it would change at the next deployment.
- **Keep the same `GWSA_ROOT`.** Accounts are shared: no
  reconnection to try a version.

Reminder: the MCP server and the broker are two processes. The server builds the
commands, the broker runs them and applies locks, policy and zones. Two
versions on the same port share the first broker started — the result
then matches neither of them.

The development lane starts with no accounts: `mag dev deploy --isolated`
creates `~/.config/gws-accounts-dev` and copies `client_secret.json` there from
prod (the OAuth app only — not the tokens). You still need to connect at least
one test account (`GWSA_ROOT=… mag add <alias>`) — human action, once.
That is the price of isolation: your work-in-progress code does not see your real
accounts.

To validate a PR from a worktree: `./bin/mag dev test` deploys the
current branch, restarts the admin on the deployed code and prints a summary
(id, URL, `afSearchHits` marker). See [PR_VALIDATION.md](PR_VALIDATION.md).

## v1 limits

- No Gmail send tool (drafts only).
- No Calendar/Docs/Sheets as MCP tools (same gateway, later).
- No token broker: a free shell can still bypass — mitigations
  in [threat-model.md](threat-model.md).
