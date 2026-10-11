# The PR "Validation" convention

> Referenced by `.github/PULL_REQUEST_TEMPLATE.md` (the template only carries the
> skeleton; the substance lives here). Derived from `ezk-pr-pilot` / ADR-0009
> (mega-city), adapted to this CLI + local admin repo.

**The principle: a PR must be testable by someone who does not have the context.**
Not "tested ✅", but *what* was tested, *how* to replay it, *what* remains,
and *which observable signal* says pass/fail.

## 1. The modality matrix

Each PR declares where it stands on **every** modality — `✅ done` (with the
method), `⏳ remaining` (with the plan), or `N.A.` (with the reason):

| Modality | What |
|---|---|
| **CI** | the repo's pipeline (link to the run) |
| **Unit / hermetic tests** | `./scripts/test.sh` — new cases listed |
| **Admin / local UI** | `mag admin` + real walkthrough + **commands to replay** |
| **CLI (`mag`)** | literal commands + expected output / exit code |
| **Before / after (UI)** | before/after screenshots · or **N.A.** if no UI change |
| **Deployment preview** | **N.A.** (no remote preview — local tool) |

## 2. The "Local test method" block — copy-pastable

**Literal commands**, in order, from a fresh worktree / clone: worktree path,
`mag admin stop` if needed, admin startup, `mag dev …` where applicable, URL to open,
UI actions. The tester must not have to **infer anything**.

### Shortcut for the current worktree / branch

A single command deploys the current clone, restarts the admin on the deployed code,
and prints a summary (id, URL, `afSearchHits` marker, process):

```bash
cd <worktree-ou-clone>
./bin/mag dev test
```

Useful options:

- `--no-deploy` — reuse the last deployment of this branch+SHA
- `--isolated` — lane without prod accounts (`~/.config/gws-accounts-dev`)
- `--open` — open `http://127.0.0.1:4877` in the browser (macOS)

Minimal pass/fail signal: the line `PR marker  : yes — PR marker afSearchHits present`
in the summary (CLI output in English, backlog item 0019), and the admin responds on
the printed URL.

## 3. Observable pass/fail signals

Each criterion has its signal: exact CLI message, expected admin page, MCP entry
written, log line. "It works" is not a signal.

## 4. Secrets

Never paste tokens, `client_secret.json`, or `gws auth export` output into the PR
body. Paths (`~/.config/gws-accounts/`) may be cited; the content may not.
