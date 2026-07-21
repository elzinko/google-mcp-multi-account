# Modèle de menace — google-mcp-multi-account

Document frère : architecture détaillée → [architecture.md](architecture.md).

## Objectif

Permettre à un ou plusieurs clients LLM (Claude Desktop, Cursor, Claude Code, …)
d’accéder à **plusieurs comptes Google** en local, **sans faire confiance au LLM
par défaut** : lecture/écriture limitées par policy, verrous, zones Drive, et
élicitation humaine pour élargir l’accès.

## Surfaces de confiance

| Composant | Rôle | Confiance |
|-----------|------|-----------|
| Humain | unlock, grant, policy, OAuth | Racine de confiance |
| Admin `127.0.0.1:4877` | Cockpit | Processus local ; pas d’auth app |
| `bin/gwsa` + `scripts/policy-check.py` | Garde-fous CLI | Appliqués si on passe par eux |
| `gateway/` + `bin/google-mcp` | Porte d’entrée MCP | Même policy/lock ; tools curatés (pas de send) |
| `gws` + `~/.config/gws-accounts/` | Tokens + appels Google | **Capacité réelle** d’accès aux données |

## Phase 1 (actuelle) — ce qui est garanti

- Profil créé via `gwsa add` → **policy prudente** (Drive zones vides, Gmail sans envoi, services non listés refusés).
- Service absent de `policy.json` → **default-deny** (sauf `auth` / `schema`).
- Profil verrouillé → refus via `gwsa` **et** via MCP.
- Tools MCP : Gmail lecture + brouillons, Drive lecture + create sous zones ; **pas** d’outil d’envoi.
- `access_request` propose unlock/grant **sans les exécuter**.
- Touch ID (`gwsa strongauth`) : présence physique pour unlock/grant (chemin absolu `/usr/bin/swift` + script repo).

## Phase 1 — ce qui n’est **pas** garanti

Un agent avec **shell libre** et accès filesystem peut encore :

```bash
GOOGLE_WORKSPACE_CLI_CONFIG_DIR=~/.config/gws-accounts/<alias> gws …
```

et contourner lock, policy, journal et MCP. L’élicitation contrôle le **comportement
coopératif** ; elle ne retire pas la **capacité** tant que les credentials sont
utilisables par `gws` hors gateway.

**Mitigation recommandée** (clients avec shell : Claude Code, Cursor Agent) :

- Chemin supporté pour les données Google = **MCP uniquement** (`bin/google-mcp`).
- Restreindre / refuser dans les permissions bash : `gws`, `GOOGLE_WORKSPACE_CLI_CONFIG_DIR=…`,
  lecture/écriture de `~/.config/gws-accounts/`.
- Ne pas mettre `gws` dans le PATH de l’agent si possible ; l’humain garde `gwsa` pour l’admin.

## Phase 2 (prévue, non implémentée) — broker de tokens

Remplacer `gateway/executor.py` (subprocess `gws`) par un process local qui :

1. détient seul les credentials ;
2. applique policy/lock/grants ;
3. appelle Google ;

sans laisser les tokens ni un `gws` utile dans le périmètre de l’agent.
L’API `gateway.api` et les tools MCP restent stables — seul l’executor change.

## Phase 1 — profils legacy

Un profil **sans** `policy.json` (créé avant ce durcissement) reste non filtré
par le checker tant que tu n’en poses pas une. Pour basculer : préréglage
« prudent » dans l’admin, ou recopier `gateway/default_policy.py`.

## Journal d’audit

`~/.config/gws-accounts/usage.jsonl` — champ `client` via `GWSA_CLIENT`
(`mcp`, `claude-code`, `cli`, …). Spoofable : utile pour le debug, pas une identité forte.
