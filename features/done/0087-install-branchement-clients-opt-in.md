---
id: 0087
title: install.sh — brancher les clients LLM en opt-in (pas opt-out)
type: feature
priority: P2
version:
epic:
status: shipped
ready: 2026-08-20
pr: "#123"
created: 2026-08-18
---

## En clair

Avant, l'installeur `curl | bash` **éditait en silence** les configs de Claude Desktop et
Claude Code — l'inverse de la doctrine « l'humain tient chaque porte ». Désormais l'install
**ne touche aucun client** par défaut : elle **imprime** le geste (`mag wire desktop` /
`mag wire code`, Cursor à la main) ; on ne branche que sur opt-in explicite (`--wire` ou
`GWSA_WIRE=1`).

## Contexte / Problème

`install.sh` **branche aujourd'hui les clients par défaut** (opt-out) : il édite les configs de
**Claude Desktop** et **Claude Code** sauf si `GWSA_SKIP_WIRE=1`. Deux problèmes :

- **Contraire à l'éthos du projet** — « l'humain tient chaque porte », default-deny, l'agent
  *propose la commande* et l'humain l'exécute (élicitation, OAuth/IAM). Éditer en silence le config
  d'un client (`claude_desktop_config.json`…) est exactement l'inverse : ça mute un fichier que
  l'utilisateur possède, sans geste explicite.
- **Norme de l'écosystème** — les serveurs MCP et les CLI (brew, `gh`, `aws`, `code`) n'auto-
  configurent pas les autres apps. Le branchement est un **geste explicite** (`claude mcp add …`,
  coller un snippet JSON, `code --install-extension`). Et **Cursor** — pourtant cité sur la landing —
  n'est de toute façon **pas** branché par l'install.

## Proposition

Passer le branchement en **opt-in**. Au choix (à trancher à l'implémentation, ordre de préférence) :

1. **Imprimer la commande** exacte à lancer pour chaque client (comme pour OAuth/IAM) — le plus
   cohérent avec la doctrine « l'agent propose, tu exécutes ».
2. **Demander** interactivement en TTY (« Brancher Claude Desktop maintenant ? [o/N] »), et imprimer
   les commandes en mode piped (non-interactif).

Inverser le flag : `GWSA_SKIP_WIRE` (opt-out) → `GWSA_WIRE=1` / `--wire` (opt-in). Documenter les
**trois** clients supportés (Desktop, Code, Cursor) et leur geste de branchement.

## Critères d'acceptation

- [x] `install.sh` par défaut **ne modifie AUCUN** config client — il imprime le(s) geste(s) à faire.
- [x] Un opt-in explicite (flag `--wire`/`GWSA_WIRE=1`, ou réponse `o` en TTY) branche Desktop/Code.
- [x] Le README / la doc d'install listent les 3 clients et leur commande de branchement — testé
      (au moins : le message d'install imprime bien les gestes ; pas de mutation par défaut).
- [x] Non-régression : les tests hermétiques d'install passent (`./scripts/test.sh`).

## Comment vérifier

- `bash install.sh --help` → l'aide mentionne `GWSA_WIRE=1|--wire`.
- **Défaut** (hermétique) : `install.sh` avec `GWSA_DESKTOP_CONFIG=/tmp/d.json`, **sans** `--wire`
  ⇒ `/tmp/d.json` **absent** et la sortie imprime `mag wire desktop`.
- **Opt-in** : idem `+ --wire` (ou `GWSA_WIRE=1`) ⇒ `/tmp/d.json` **créé**, contient `google-multi-account`.
- Suite : `./scripts/test.sh` — assertions « opt-in, fiche 0087 » (384 réussis / 0 échoué).

## Notes

- **Livré (POC)** : opt-in par **flag/env** (`--wire` / `GWSA_WIRE=1`). Le **prompt TTY** (approche 2)
  est un **polish différé** — le flag satisfait la DoR ; `curl | sh` et la CI restent print-only.
- **Revue** : `ezk-reviewer` GO (0 P0/P1) ; P2 « garde-fou honore `CLAUDE_BIN` » corrigé, P2
  « `--help` via `curl|bash` » (pré-existant, hors-diff) capté à part.
- Soulevé pendant le lot « toilettage doc » (wording « branche tes clients » sur la landing). Le
  wording a été corrigé côté doc (Desktop+Code, Cursor à la main) ; **cette fiche** traite le
  **changement de comportement** de l'installeur.
- Infra `GWSA_*` à préserver (cf. renommage `mag`). Axe install/deploy, hors épic droits-par-session.

## Grooming (PO — 2026-08-20)

Tirée **avant** le head P1 0019 (docs anglaises) : 0019 dépend de l'épic 0017 (idée) et
exige des arbitrages produit. Skip **assumé et journalisé** (choix humain au checkpoint
« aucune fiche ready »).

**Périmètre tranché (DoR) :**

- **Défaut = aucune mutation** de config client. `install.sh` **imprime** le geste de
  branchement de chaque client (doctrine « l'agent propose, tu exécutes »).
- **Opt-in POC** = flag/env explicite `--wire` / `GWSA_WIRE=1` → branche Desktop + Code.
  Déterministe → **testable en hermétique**. Retire/inverse `GWSA_SKIP_WIRE`.
- **Opt-in polish** = prompt TTY (« Brancher X ? [o/N] ») **avec repli print-only** si
  non-interactif / piped — `curl | sh` et la CI ne mutent **jamais**.
- **Docs** = README + doc install listent les **3** clients (Desktop & Code branchables ;
  Cursor = snippet manuel) et leur geste.
- **Non-régression** = `./scripts/test.sh` vert + test « défaut ⇒ 0 mutation, opt-in ⇒ mutation ».
- Préserver le nommage `GWSA_*` ; mettre à jour tout call-site / doc référençant `GWSA_SKIP_WIRE`.

DoR : problème clair · périmètre tranché · critères testables · harnais identifié → **prêt à tamponner**.
