# ADR-0002: The profile email is persisted identity metadata — outside the lock, outside gws

**Status:** Accepted
**Date:** 2026-07-24
**Decision makers:** Thomas (PO)

> **TL;DR** — The email address of each connected Google account is now remembered in a small text file written at connection time, instead of being fetched by re-running the Google tool on every read — so a "locked" account (whose data access is blocked until a human reopens it) can still display its email for setup diagnostics, without ever running the Google tool on its credentials while it is locked.

## Context

A profile's lock (`.locked`) means "data access on demand":
every data call is refused until a human `unlock`. Yet `setup_status`
(backlog item 0009) needs the email of **every** account — locked ones included —
to check the IAM role and propose the exact `gcloud add-iam-policy-binding`
command (guided onboarding, ADR-0001).

The initial implementation fetched this email by running `gws auth status`
as a direct subprocess (`GOOGLE_WORKSPACE_CLI_CONFIG_DIR=… gws …`) from
`gateway/profiles.py::_profile_email`:

1. **Outside the broker** — whose contract is "the only process that runs gws"
   on the gateway side; and precisely the pattern the threat model asks us to
   block in agents.
2. **On a locked profile** — the branch ran *only* in that case
   (`list_profiles` only reads the email when unlocked): running gws means
   touching the encrypted credentials during the lock.
3. **Inconsistent** — `profiles_list` hid the email of locked profiles,
   `setup_status` displayed it.

The product posture is already written down (SECURITY.md): "A locked profile
refuses all data access […] The only metadata that stays readable: the account
email, for diagnostics (`setup_status`)."

## Decision

**Own the exception — the email stays readable on a locked profile — but
change its nature: it is persisted metadata, no longer the result
of a gws execution.**

- At connection time (`mag add`, human action), the email is written in clear to
  `<profile>/.email`. `mag list` and the admin backfill profiles created
  before this decision, as soon as they read a non-empty email.
- All surfaces (**`profiles_list`, `setup_status`, admin, mag**)
  read this file. The gateway no longer launches any gws subprocess for this.
- The invariant becomes sharp and testable: **lock ⇒ zero gws executions with
  the profile's credentials**, and `gateway/` contains no
  `GOOGLE_WORKSPACE_CLI_CONFIG_DIR` outside `broker_server.py` (static test).
- File missing (legacy profile): empty email, IAM "unknown", and
  `next_actions` suggests `mag list` (the backfill is a human pass).
  Content that is not an email is ignored (no blind trust).

## Options considered

### Option A — Own the exception via the broker (derogation from the lock)

| Dimension | Assessment |
|---|---|
| Consistency | Broker as sole executor: yes — at the price of an "auth status even when locked" derogation |
| Security | gws still runs on a locked profile (credentials touched) |
| Complexity | Dedicated broker command + carve-out in `require_unlocked` |

**Pros:** centralizes and logs the exception. **Cons:** installs a derogation
from the lock in the most sensitive component, for a piece of data that
does not need to be recomputed on every read. **Rejected.**

### Option B — Align `setup_status` with `profiles_list` (no email when locked)

| Dimension | Assessment |
|---|---|
| Consistency | Total, by leveling down |
| Security | The strictest |
| Onboarding UX | Broken in the recommended posture: locked profile ⇒ no more IAM check or remediation |

**Pros:** simple, nothing to write. **Cons:** contradicts the raison d'être of
`setup_status` (ADR-0001: give Desktop the visibility of
`provision-gcp.sh status`) and the sentence already published in SECURITY.md.
**Rejected.**

### Option C — Persisted `.email` metadata (chosen)

| Dimension | Assessment |
|---|---|
| Consistency | All surfaces read the same source; broker is once again the sole executor |
| Security | Lock ⇒ zero gws executions; the email is captured at the human `add` action |
| Onboarding UX | Preserved (IAM + remediation even when locked) |
| Bonus | No more gws subprocess (15 s timeout) per profile in `profiles_list` |

**Pros:** delivers the result of A with a stronger invariant than B asked
for. **Cons:** one more file per profile + backfill of existing
profiles — accepted (the folder already contains `client_secret.json` in clear,
far more sensitive than an email).

## Consequences

- Becomes simpler: `setup_status` (no more special case),
  the doctrine ("the lock blocks *all* gws execution"), the hermetic tests
  (the email is tested without a gws binary).
- Becomes more demanding: `.email` can drift if someone runs
  `gws auth login` by hand outside `mag` (unsupported path) — the
  `mag add`/`mag list` passes re-synchronize it.
- SECURITY.md stays true word for word; threat model updated
  (section "Email = identity metadata").
