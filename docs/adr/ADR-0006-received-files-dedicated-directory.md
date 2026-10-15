# ADR-0006: Received files land in a dedicated download directory

**Status:** Accepted
**Date:** 2026-07-29
**Decision makers:** Thomas (PO)

> **TL;DR** — Received files (the email attachments downloaded to disk) always land in a single dedicated, locked-down download folder, and the program never lets the AI assistant choose where to write nor overwrite an existing file — because an attachment is third-party content that may be booby-trapped, and letting a manipulated AI (via a malicious email) choose the path would allow overwriting sensitive system files or exfiltrating a local secret.

## Context

Backlog item 0043 brings **inbound** files into the system:
`gmail_attachment_get` materializes an attachment on the local disk.
ADR-0003 settled the **outbound** direction (content written by the LLM → `.uploads`
deposit → gws); nothing framed the reverse direction.

An attachment is **third-party content**: written by the email's sender,
not by the user or the LLM. The file name and the content are both
potentially hostile. And the tool's `filename` parameter is supplied by the
LLM — that is, in case of prompt injection via a read email, by the attacker
themselves.

## Decision

**Create a dedicated download directory, `<GWSA_ROOT>/.downloads`
(0700), the only possible destination for received files.**

- The tool accepts **no destination path**: only an indicative `filename`,
  reduced to a sanitized base name (never hidden, never empty,
  never containing a separator).
- **Never overwrite**: creation with `O_CREAT|O_EXCL` (0600), numeric suffix
  if the name already exists. Two downloads = two files.
- The final path is **returned** to the caller: it is the MCP client (Claude
  Code, the human) that then decides to copy the file into a project —
  an action outside the gateway, under its own permissions.
- Symmetry on the outbound side: `drive_upload` refuses to read under `GWSA_ROOT`
  (tokens, credentials, policies) — except for `.downloads`, so that
  "receive an attachment then drop it on Drive" remains a direct sequence.
- The leading dot (`.downloads`) keeps it out of profile enumerations,
  like `.uploads` (ADR-0003).

## Options considered

### Option A — Free `output_path` parameter

| Dimension | Assessment |
|---|---|
| Ergonomics | The best (the file arrives where you want it) |
| Security | Arbitrary write of attacker-controlled content: a booby-trapped email that convinces the LLM to write `~/Library/LaunchAgents/x.plist` or `~/.zshrc` becomes an execution vector |

**Rejected**: the pairing "third-party content + path chosen by the LLM" is
exactly what the project's threat model forbids.

### Option B — Dedicated directory, path returned (chosen)

| Dimension | Assessment |
|---|---|
| Security | Write surface = one 0700 directory, unique names, zero overwrite |
| Ergonomics | One extra `cp` for the caller — path provided, trivial action |
| Consistency | Exact mirror of `.uploads` (ADR-0003): one lane per direction |

### Option C — Return the binary as base64 in the MCP response

| Dimension | Assessment |
|---|---|
| Simplicity | No local file |
| Practicality | A 500 KB logo = ~700 KB of base64 injected into the LLM's context; a PDF catalog makes it overflow |

**Rejected**: the content has to end up on disk anyway; making it
pass through the model's context only adds loss.

## Consequences

- Becomes possible: retrieving an attachment (logo, catalog, PDF) and
  reusing it — including re-uploading it to Drive via `drive_upload`.
- Becomes impossible by construction: overwriting an existing file or writing
  outside `.downloads` from an MCP tool.
- The directory is never purged automatically: files accumulate there
  until a human cleanup (same status as `usage.jsonl` —
  candidate for the cleanup in backlog item 0028).

## Source of `drive_upload` — allowlist (default-deny)

Symmetry of `.downloads` on the outbound side: the **source** of a `drive_upload` is
restricted to an **allowlist** of folders, not the whole disk. Otherwise a
`drive_upload("~/.ssh/id_rsa", <granted zone>)` induced by prompt injection
would exfiltrate a local secret — **reachable through the MCP alone, without a shell**.

Folders allowed for reading:

- `<GWSA_ROOT>/.downloads` — always (re-upload a received attachment);
- those declared by the human, in two cumulative ways:
  - **file `<GWSA_ROOT>/.upload-roots`** (recommended): one absolute path per
    line, `#` = comment. It lives with the rest of the config, so it **survives
    redeployments** — the env, by contrast, is rewritten by the installers
    (`install-claude-*.sh`) and is lost on update;
  - **`GWSA_UPLOAD_ROOTS`** variable (absolute paths separated by `os.pathsep`).

Deliberately **outside the git repository** (a deliverable does not have to live in the
sources) and **outside `GWSA_ROOT`** (tokens): the human explicitly opens the
folders the LLM may read from. By default the list is empty → only
`.downloads` is readable; drop the file to upload into `.downloads`,
or declare its folder. The `.upload-roots` file is **not modifiable by
the LLM** (no tool writes under `GWSA_ROOT`); its leading dot keeps it out of
profile enumerations. A hard guard additionally refuses any read under
`GWSA_ROOT` (outside `.downloads`) even if the allowlist covered it by mistake.

A **denylist** of sensitive paths was ruled out (fragile, never
exhaustive, false assurance). Defense in depth beyond the
allowlist: Drive writing requires an **active zone** anyway (human
grant, never granted by the LLM) and the call remains **visible** in the trace.
