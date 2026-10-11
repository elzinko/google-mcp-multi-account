# Contributing

Want to lend a hand? This project is small, local, and free of heavy machinery — you
can get into it quickly. Here is the path, from clone to merged PR.

## Getting started

```bash
git clone https://github.com/elzinko/google-mcp-multi-account
cd google-mcp-multi-account
./scripts/test.sh          # the hermetic suite — no real account, no network
```

If the suite is green, your environment is good. You need **Python 3**; the Google
`gws` CLI is only needed for a test with *real* accounts (the automated tests use
none).

To see the admin interface running on your code:

```bash
./bin/mag dev test         # deploys the current clone, starts the admin, prints the URL
```

## How the work is organized

- **The backlog lives in the repository.** Every idea, bug or feature is a markdown
  backlog item in `features/` (one per topic; the front matter carries the status).
  That is where you see *what is left to do* and *what has shipped* (`features/done/`).
- **One PR per topic.** Start from a branch and keep the PR focused.
- **Commit messages** follow [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat:`, `fix:`, `docs:`…) — this is what feeds the CHANGELOG and versioning.
- **Automated review**: every PR gets a review (Codex); address the feedback before
  merging.
- **Merge when green**, usually as a *squash*.

## Two safeguards to respect

These are the project's security invariants — breaking them silently is the only real
"no":

- **Never** commit or display secrets: tokens, `client_secret.json`, the output of
  `gws auth export`. Cite *paths* (`~/.config/gws-accounts/`), never the content — see
  [SECURITY.md](https://github.com/elzinko/google-mcp-multi-account/blob/main/SECURITY.md).
- **Do not bypass** the safeguards (default-deny policy, locks, Drive zones): they are
  the heart of the project. If a need gets in their way, open the discussion in a
  backlog item rather than weakening them.

## Validating your PR

A good PR is **testable by someone who does not have the context**: not a bare
"tested ✅", but *what* was tested, *how* to replay it, and *which observable signal*
says pass or fail. The full convention (modality matrix, copy-pastable command block,
pass/fail signals) is detailed in **[PR validation](PR_VALIDATION.md)**.

## Going further

- **[Under the hood](architecture.md)** — how the pieces fit together, where the safeguards are.
- **[GitHub security](github-security.md)** — the repository's security configuration.
- A design decision puzzles you? The **[ADRs](adr/ADR-0001-onboarding-by-elicitation.md)**
  explain *why* the project decided the way it did.
