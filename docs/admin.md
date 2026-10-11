# Admin interface

A local web app to manage accounts, locks, policies, and Drive zones from the browser — the graphical alternative to the [`mag`](usage.md) CLI.

```bash
mag admin                 # starts (detached, idempotent) + opens http://127.0.0.1:4877
mag admin stop            # stops; logs in ~/.config/gws-accounts/admin.log
```

*(manual equivalent: `node admin/server.js` — local only)*. The
MCP elicitation messages quote the command, so any LLM client
can offer to start it for you when it is useful.

Everything is driven from the browser: **connect an account** (alias + expected
email — the Google tab opens with the right account preselected and the
connection is refused if you pick the wrong one), **lock/unlock**
(minutes or `off`), **edit the policy** service by service with presets
("cautious": Drive zones, Gmail drafts without sending, Calendar read, Keep
read + create), **access log** (who did what on which account —
LLMs identify themselves via the `GWSA_CLIENT` variable), **built-in docs** (❓:
installation, sequence diagrams, MCP tools, OAuth setup) and a **big Revoke
button** (deletes the tokens from the machine, access cut immediately).

Add an authorized folder without ever typing an ID: **🔍 search by name**
(several matches → a pick list with the full path) or **📂
browse** My Drive (Open/Choose), then pick a duration: temporary (default
8 h) or permanent. *(Why IDs internally? Drive folder names are not
unique and change as folders are renamed or moved; the ID is the
only stable reference. The interface converts name → ID for you.)*

Security: server bound to 127.0.0.1 only, mandatory custom header
(anti-CSRF), Origin checked, no npm dependency (mermaid vendored
locally), actions delegated to `bin/mag` (`execFile`, never a shell).
