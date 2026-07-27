---
id: 0040
title: Le déploiement branche Claude Desktop mais pas Claude Code (CLI) — généraliser
type: feature
priority: P2
version:
epic:
status: todo
ready: 2026-07-27
pr: "#43"
created: 2026-07-27
---

## Contexte / Problème

Constaté à l'usage (2026-07-27) : un `claude` (Claude Code, le CLI) démarré
depuis n'importe où **ne liste pas** le serveur `google-multi-account`. Vérifié :
`~/.claude.json` (user + projets) ne contient que d'autres serveurs ; aucune
entrée `google-multi-account`, aucun `.mcp.json` dans le repo.

Cause : le flux de déploiement (`update.sh` → `install-claude-desktop.sh`) ne
branche que **Claude Desktop** (son fichier JSON dédié). **Claude Code** a une
config séparée (`~/.claude.json`) et n'a jamais été enregistré. Deux applis,
deux configs — brancher l'une ne branche pas l'autre.

## Proposition

Un pendant `install-claude-code.sh`, câblé dans `update.sh`, qui enregistre le
serveur côté Claude Code **au scope user** via le CLI officiel — jamais en
éditant `~/.claude.json` à la main (fichier d'état vivant : permissions,
historique ; l'éditer risque la corruption + une course avec un Claude Code
ouvert). Idempotent, best-effort (CLI absent → on n'échoue pas le déploiement).

## Critères d'acceptation

- [x] `install-claude-code.sh` enregistre au scope **user** via
      `claude mcp add … --env GWSA_CLIENT=claude-code --env GWSA_BROKER_PORT=4878`.
- [x] **Idempotent** : déjà bon → rien ; pointe ailleurs → remove + re-add ;
      relance sans doublon.
- [x] **Dégradation gracieuse** : `claude` absent du PATH → avertissement +
      `exit 0` (le déploiement n'échoue pas).
- [x] `--print` montre la commande sans invoquer le CLI.
- [x] `update.sh` branche **les deux** clients (Desktop + Code si `claude` présent).
- [x] Tests hermétiques (mock `claude` via `CLAUDE_BIN`) : le vrai `~/.claude.json`
      n'est jamais touché.
- [x] Docs (README + docs/mcp-setup.md) : le déploiement branche les deux clients.
- [x] `./scripts/test.sh` vert.

## Notes

- Le port 4878 est partagé avec Desktop : même couloir stable, mêmes comptes
  (fiche 0025 — un port distinct sert à isoler des VERSIONS, pas des clients).
  `GWSA_CLIENT` distingue les deux clients dans le journal (`claude-desktop` vs
  `claude-code`).
- Le mock des tests capture les appels `claude mcp add/get/remove` : impossible
  de tester en touchant la vraie config, d'où la délégation via `CLAUDE_BIN`.
