# Sécurité GitHub — ce qui est activé / ce qui reste manuel

Source de vérité live : [Security settings](https://github.com/elzinko/google-mcp-multi-account/settings/security_analysis)
et l’onglet [Security](https://github.com/elzinko/google-mcp-multi-account/security).

## Fait via API / fichiers

| Mesure | Où | Statut |
|---|---|---|
| **Dependabot alerts** | Settings → Code security | Activé |
| **Dependabot security updates** | idem | Activé |
| **Private vulnerability reporting** | idem | Activé (aligné avec `SECURITY.md`) |
| **Secret scanning** | idem | Activé (repo public) |
| **Push protection** (secrets) | idem | Activé |
| **CodeQL default setup** | Code scanning | Activé via API (`state: configured`) — Python / JS-TS / Actions |
| **`dependabot.yml`** | `.github/dependabot.yml` | Ecosystème `github-actions` (hebdo) |

## Reste manuel (owner UI) ou non applicable

| Mesure | Pourquoi |
|---|---|
| **Secret scanning — non-provider patterns** | PATCH API accepté mais statut reste `disabled` — cocher dans Settings → Code security si l’option apparaît. |
| **Secret scanning — validity checks** | Idem. |
| **pip / npm Dependabot** | Aucun `package.json` / `requirements.txt` (stdlib + mermaid vendorisé). Ajouter une entrée dans `dependabot.yml` le jour où un manifeste apparaît. |
| **Branch protection + required checks** | Optionnel : Settings → Branches (exiger CI + CodeQL sur `main`). |
| **Workflow CodeQL avancé** | Non ajouté — default setup suffit ; un `.github/workflows/codeql.yml` ferait doublon. |

## Rappels produit (hors GitHub)

Voir [`SECURITY.md`](https://github.com/elzinko/google-mcp-multi-account/blob/main/SECURITY.md) et [`threat-model.md`](threat-model.md) :
policy default-deny, strongauth / Touch ID, élicitation, broker, journal — ce n’est
pas remplacé par Dependabot / CodeQL.
