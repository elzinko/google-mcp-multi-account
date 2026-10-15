# ADR-0003: The content of a Drive file goes through the broker's deposit directory

**Status:** Accepted
**Date:** 2026-07-26
**Decision makers:** Thomas (PO)

> **TL;DR** — So that an agent can drop an already-written document (converted to a Google Doc) into the right account's Drive, rather than an empty file, the text is written to a temporary file in a dedicated, locked-down folder (`.uploads`) from which the command-line tool runs, then erased right away — this detour is forced because that tool only accepts a file path (no in-memory content) and refuses any path outside its working directory.

## Context

`drive_create` could only set metadata (`name`, `mimeType`,
`parents`): it created **empty** files (backlog item 0024). Yet the real use
is "drop a written deliverable into the right account's Drive" — that is the
project's raison d'être, since the other Drive connectors write content but
to the wrong account.

The Drive API expects a **multipart upload** (metadata + media in the same
request); this is also what triggers the conversion of `text/markdown` or
`text/plain` → `application/vnd.google-apps.document`. On the CLI side, this is written:

```
gws drive files create --json '{…}' --upload <fichier> --upload-content-type text/markdown
```

Two constraints frame the solution:

1. **gws does not accept in-memory content** — only `--upload <path>`.
   The text therefore has to be materialized in a file.
2. **gws refuses any path resolved outside its current directory**:
   `--upload '/tmp/x.md' resolves to '/private/tmp/x.md' which is outside the
   current directory`. A classic `tempfile` in `/tmp` is therefore unusable:
   gws's cwd is that of the **broker**, which depends on how it was
   started (`REPO_DIR` on automatic start, arbitrary when started by hand).

On top of this comes the project doctrine (ADR-0002): the broker is the only process that
runs gws; the gateway launches no gws subprocess.

## Decision

**Create a dedicated deposit directory, `<GWSA_ROOT>/.uploads` (0700), and have
the broker run gws with this directory as its current directory.**

- The gateway writes the content there to a temporary file (0600, created by
  `mkstemp`), passes its path as `--upload`, and **always erases it**
  (`finally`), on success and on failure.
- The broker sets `cwd=<deposit>` for **all** its gws calls, not just
  uploads: gws's file sandbox becomes the deposit directory instead of
  the git repository.
- The path is derived from `gwsa_root()` on both sides — the gateway and broker
  already share `GWSA_ROOT` (token, pidfile, `usage.jsonl`), and a lane
  (stable / dev, backlog item 0023) has its own deposit.
- `parents` stays in `--json`: it is the only place that `policy-check.py`
  reads to check the write zone. Drive zones therefore apply to the content
  deposit exactly as they do to the creation of an empty file.
- The directory starts with a dot: the three profile enumerators
  (`gateway/profiles.py`, `bin/mag`, `admin/server.js`) filter on
  `ALIAS_RE`, so it never shows up as an account.

## Options considered

### Option A — Temporary file in `/tmp`, absolute path

| Dimension | Assessment |
|---|---|
| Simplicity | Maximal (about ten lines, zero coordination) |
| Works | No — gws refuses the path outside cwd |

**Rejected**: it does not work. Constraint no. 2 closed this door.

### Option B — Shared deposit directory + broker cwd (chosen)

| Dimension | Assessment |
|---|---|
| Broker protocol | Unchanged (still "a list of arguments") |
| ADR-0002 doctrine | Respected — the gateway writes a file, it still does not run gws |
| Security | gws's sandbox **narrowed**: from the git repository to the deposit directory alone |
| Failure on a stale broker | Explicit (`outside the current directory`), never silent |

**Pros:** no protocol change, hence no version negotiation
between a new gateway and an already-running broker; and a gws cwd narrower
than before for *all* commands. **Cons:** responsibility is
shared (the gateway writes the file, the broker sets the cwd) — two pieces
of code must agree on a path. The coupling already exists (`GWSA_ROOT`)
and a hermetic test locks it down.

### Option C — Extend the broker protocol (`media` field)

The content would travel in the RPC request; the broker would write the file,
add `--upload`, then clean up.

| Dimension | Assessment |
|---|---|
| Consistency | The best: the broker owns everything gws touches |
| Protocol | Changes — a broker **already running** (old code) ignores `media`… |
| Failure on a stale broker | …and creates an **empty** document **without reporting anything** |

**Pros:** single ownership of the media file. **Cons:** the broker is a
daemon that outlives code updates (`deploy-local.sh` recycles it
precisely for that): a silently ignored field produces silent
data loss. A capability negotiation (or a separate command) would be needed to make the failure explicit — extra machinery for
zero gain in trust here (gateway and broker are the same user, the same
deployed code, and the broker already trusts the gateway's arguments
subject to policy). **Rejected for now**; to reconsider if the
broker ever had to serve clients less trustworthy than the local gateway.

### Option D — Create empty, then write via the Docs API

`drive files create` (empty) then `docs documents batchUpdate` /
`gws docs +write`.

| Dimension | Assessment |
|---|---|
| Policy | Blocked in practice: undeclared `docs` = refused (default-deny) |
| Atomicity | Two calls — "empty document" intermediate state on failure |
| Rendering | Plain text only: no headings, lists, or bold |

**Rejected.**

## Consequences

- Becomes possible: dropping a **written** deliverable into the right account, in one
  request, converted to a Google Doc (markdown by default when the target is a
  Google type — that is the format in which agents write).
- Becomes safer: gws now runs from an empty deposit directory
  rather than from the git repository; a crafted `--upload` can no longer
  point at a project file.
- Becomes more demanding: a broker launched **before** this version keeps
  serving the old code and will refuse the upload (`outside the current directory`).
  Remedy: `mag broker stop` (it restarts by itself on the next call) —
  this is already what `scripts/deploy-local.sh` does.
- Content written by the LLM touches the disk, in clear, for the duration of one call
  (0600, in a 0700 directory, erased in `finally`). This is the same level
  of exposure as `usage.jsonl`, which already logs command arguments,
  and far lower than the credentials in the same directory.
