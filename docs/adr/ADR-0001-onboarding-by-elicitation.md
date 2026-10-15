# ADR-0001: Onboarding guided by the MCP — elicitation, never execution

**Status:** Accepted
**Date:** 2026-07-22
**Decision makers:** Thomas (PO)

> **TL;DR** — To make configuration lighter, the local server that links the AI assistant to the Google accounts will guide the user by diagnosing what is missing and displaying the exact commands to paste, but it will limit itself to reading and proposing: the human always runs the sensitive actions (connecting an account, opening rights), so that the AI can never widen access on its own.

## Context

The README gives the impression of a heavy configuration: GCP provisioning,
console steps, `mag add` per account, IAM roles, MCP wiring, policies…
The product request: the human only does the **GCP init** (reliable and
simple), and **everything else** is driven from the LLM client via the
MCP — a guided "init", and connection of new accounts by elicitation
with strong authentication.

Architecture facts that constrain the answer:

1. **Google forbids automating** the creation of the OAuth "Desktop
   app" client and the publication of the app. No tool (script, MCP, Terraform) will
   remove these 2 console steps. `provision-gcp.sh` already guides them.
2. The project's **security model** rests on: *the tool verifies,
   the human authorizes, the LLM proposes*. Any mutation that widens access
   (unlock, grant, account connection, IAM binding) requires a human action.
3. In **Claude Desktop, there is no shell**: the MCP server is the
   only bridge. Yet today the whole setup diagnostic (`provision-gcp.sh
   status`, enriched `mag list`) exists only in a terminal — a Desktop user
   cannot be guided.
4. The elicitation building blocks already exist (PRs #5/#6/#7):
   `access_request` kind=`add_account` (email required, Touch ID on `mag
   add`), post-connection IAM probe, `status` with IAM drift, idempotent
   `sync-iam`.

## Decision (proposed)

Make onboarding a **dialogue guided by the MCP**, keeping the line
"elicitation, never execution":

- Add a read-only **`setup_status`** MCP tool that aggregates the full
  setup state — provisioned project, published app, `client_secret`,
  connected profiles, IAM role per account, locks/policies — by reusing
  `provision-gcp.sh status` (to be given a `--json` output). The LLM (including
  Desktop) gets a **structured checklist** and proposes, for
  each gap, the exact command: this is the requested "init", in guided
  form.
- Connecting a new account remains the **`access_request add_account`**
  elicitation (already wired): Touch ID + OAuth consent = two physical
  barriers, the human executes.
- Rewrite the **README as a 3-step quickstart** (provision → wire the MCP →
  "initialize my accounts"), with the details moving to `docs/`.

## Options considered

### Option A — Status quo (terminal-only docs)

| Dimension | Assessment |
|---|---|
| Complexity | None |
| Security | Unchanged |
| Desktop UX | Poor — no guidance possible without a shell |
| Claude Code UX | Fine (CLAUDE.md + scripts) |

**Pros:** nothing to do. **Cons:** the "complicated configuration"
impression remains; Desktop stays blind.

### Option B — The MCP executes the setup (an "init" that does everything)

| Dimension | Assessment |
|---|---|
| Complexity | Medium |
| Security | **Breaks the model** |
| UX | Excellent on the surface |

**Pros:** zero friction. **Cons:** `sync-iam`/gcloud has **no physical
barrier** — an LLM (or a prompt injection) could mutate
cloud IAM with no human in the loop; multiplying Touch ID prompts
creates approval fatigue; contradicts CLAUDE.md and the threat model.
**Rejected.**

### Option C — Read-only `setup_status` + guided elicitation (chosen)

| Dimension | Assessment |
|---|---|
| Complexity | Low (reuses status/`iam_profile_states`, JSON output) |
| Security | Model preserved — the tool only READS |
| Desktop UX | Good — checklist + ready-to-paste commands |
| Claude Code UX | Same, and the LLM can run the reads itself |

**Pros:** meets the need ("the MCP guides and helps") without touching the
model. **Cons:** the human still pastes the mutation commands — this is a
deliberate choice, not a technical limit.

### Option B′ — Deferred variant: mediated execution with a double barrier

`account_add` executed by the MCP but gated by Touch ID **and** OAuth consent
(both physical barriers remain). Defensible for this
specific action — but not for `sync-iam` (no equivalent barrier). Noted as a
possible evolution, **deferred** until the copy-paste friction is
proven to be a problem.

## Consequences

- Becomes simpler: Desktop onboarding ("initialize my accounts" →
  guided checklist), the README (3-step quickstart), diagnostics at any
  time (`setup_status`).
- Becomes more demanding: maintaining the `--json` output of `status` as the
  tool's contract; documenting the boundary "the MCP reads, the human mutates".
- To revisit: B′ if the residual friction justifies it; multi-project GCP
  (backlog items 0003/0008) out of scope.

## Scenarios validated by sequence diagrams

- [diagrams/onboarding-setup-initial](https://github.com/elzinko/google-mcp-multi-account/tree/main/diagrams/onboarding-setup-initial/) — the 3 target steps
- [diagrams/lecture-donnees-elicitee](https://github.com/elzinko/google-mcp-multi-account/tree/main/diagrams/lecture-donnees-elicitee/) — day to day: lock → elicited unlock → read under policy (existing)
- [diagrams/onboarding-add-account-elicite](https://github.com/elzinko/google-mcp-multi-account/tree/main/diagrams/onboarding-add-account-elicite/) — elicited connection (existing, PR #7)
- [diagrams/onboarding-reparation-iam](https://github.com/elzinko/google-mcp-multi-account/tree/main/diagrams/onboarding-reparation-iam/) — IAM drift: detection ×2, human repair (PRs #5/#6)

## Actions

1. [ ] Backlog item 0009: `provision-gcp.sh status --json` + `setup_status` MCP tool (read-only).
2. [ ] Backlog item 0010: README rework into a 3-step quickstart, details → `docs/`.
3. [ ] Merge the #5 → #6 → #7 stack (prerequisite: the elicitation building blocks).
