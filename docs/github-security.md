# GitHub security — what is enabled / what remains manual

Live source of truth: [Security settings](https://github.com/elzinko/google-mcp-multi-account/settings/security_analysis)
and the [Security](https://github.com/elzinko/google-mcp-multi-account/security) tab.

## Done via API / files

| Measure | Where | Status |
|---|---|---|
| **Dependabot alerts** | Settings → Code security | Enabled |
| **Dependabot security updates** | same | Enabled |
| **Private vulnerability reporting** | same | Enabled (aligned with `SECURITY.md`) |
| **Secret scanning** | same | Enabled (public repo) |
| **Push protection** (secrets) | same | Enabled |
| **CodeQL default setup** | Code scanning | Enabled via API (`state: configured`) — Python / JS-TS / Actions |
| **`dependabot.yml`** | `.github/dependabot.yml` | `github-actions` ecosystem (weekly) |

## Remains manual (owner UI) or not applicable

| Measure | Why |
|---|---|
| **Secret scanning — non-provider patterns** | API PATCH accepted but status stays `disabled` — tick it in Settings → Code security if the option appears. |
| **Secret scanning — validity checks** | Same. |
| **pip / npm Dependabot** | No `package.json` / `requirements.txt` (stdlib + vendored mermaid). Add an entry to `dependabot.yml` the day a manifest appears. |
| **Branch protection + required checks** | Optional: Settings → Branches (require CI + CodeQL on `main`). |
| **Advanced CodeQL workflow** | Not added — the default setup is enough; a `.github/workflows/codeql.yml` would duplicate it. |

## Product reminders (outside GitHub)

See [`SECURITY.md`](https://github.com/elzinko/google-mcp-multi-account/blob/main/SECURITY.md) and [`threat-model.md`](threat-model.md):
default-deny policy, strongauth / Touch ID, elicitation, broker, audit log — none of
this is replaced by Dependabot / CodeQL.
