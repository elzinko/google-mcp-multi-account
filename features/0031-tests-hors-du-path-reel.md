---
id: 0031
title: La suite de tests ne doit jamais pouvoir toucher le PATH réel
type: bug
priority: P1
version:
epic:
status: in-progress
ready: 2026-07-27
pr:
created: 2026-07-27
---

## Contexte / Problème

`update.sh` rebranche le `gwsa` du PATH sur la copie installée (fiche 0030).
Quand `GWSA_CLI_LINK` n'est pas fourni, il retombe sur `command -v gwsa` —
donc sur le **vrai** lien de la machine.

Plusieurs tests appelaient `update.sh` sans désigner de lien : ils
s'appuyaient uniquement sur la garde « je ne reprends qu'une cible du
projet ». C'est une protection dans le code testé, pas dans le harnais.

Constaté pour de vrai le 2026-07-27, pendant un test de mutation : retirer
cette garde a fait pointer `/opt/homebrew/bin/gwsa` vers le répertoire
temporaire de la suite —

```
/opt/homebrew/bin/gwsa -> /var/folders/…/T/tmp.dk9jEtstIr/reldeploy/current/bin/gwsa
```

— répertoire supprimé à la fin du test. `gwsa` était donc cassé sur la machine
jusqu'à réparation manuelle du lien.

La doctrine du projet est pourtant explicite dans l'en-tête de `scripts/test.sh` :
« tout se passe dans un `GWSA_ROOT` temporaire — tes vrais profils ne sont
jamais lus ni écrits ». Le PATH méritait la même promesse.

## Proposition

Deux verrous, pour que la promesse ne dépende plus d'une seule garde.

1. **Dans `update.sh`** : si le dépôt d'installation est surchargé
   (`GWSA_DEPLOY_ROOT`, signature d'un bac à sable) **et** que
   `GWSA_CLI_LINK` n'est pas donné, ne toucher à aucun lien — et le dire.
2. **Dans `scripts/test.sh`** : `relenv` désigne systématiquement un lien sous
   `$TMP`, pour qu'aucun appel ne puisse retomber sur `command -v gwsa`.

## Critères d'acceptation

- [x] Dépôt d'installation surchargé sans `GWSA_CLI_LINK` → aucun lien touché,
      message explicite.
- [x] Tous les appels de la suite désignent un lien sous `$TMP`.
- [x] Preuve par mutation : en retirant la garde « cible hors projet », le
      `/opt/homebrew/bin/gwsa` réel reste intact (seul le test dédié échoue).
- [x] `./scripts/test.sh` vert.

## Notes

- Le lien réel a été réparé à la main, et pointe désormais la copie installée
  (`~/.local/share/google-mcp/current/bin/gwsa`) — l'état visé par la fiche 0030.
- Leçon : un test de mutation exécute du code volontairement cassé. Le harnais
  doit être étanche **par construction**, sans compter sur les gardes du code
  qu'il malmène.
