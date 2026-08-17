---
id: 0027
title: Déployer un commit non taggé pour essayer une PR (couloir jetable)
type: feature
priority: P2
version:
epic:
status: shipped
ready: 2026-07-28
pr: "#48"
created: 2026-07-26
---

## Contexte / Problème

`deploy-local.sh` exige un HEAD taggé — garantie voulue : une version déployée
est identifiable. Effet de bord : impossible d'essayer une PR en conditions
réelles sans inventer un tag, qui pollue l'historique des versions.

## Proposition

Une étiquette explicitement jetable, par exemple
`./scripts/deploy-local.sh --as sha-9d7f985`, qui se déploie dans
`~/.local/share/google-mcp/sha-9d7f985/`, se branche sous un nom d'entrée
distinct avec son propre port (fiche 0025), et ne devient **jamais** `current`.

## Livré (PR #48)

Réalisé via `mag dev` plutôt que `deploy-local.sh --as` :

- `mag dev deploy [--isolated]` — copie le clone courant sous
  `~/.local/share/google-mcp/<id>/` (id jetable, jamais `current`)
- `list` / `status` / `use` (Cursor / Claude Desktop `--apply`) / `remove`
- Option `--isolated` + seed OAuth pour un couloir sans comptes prod
- `mag dev test` + couverture hermétique dans `scripts/test.sh`

## Critères d'acceptation

- [x] Déployer un HEAD non taggé en couloir temporaire sans toucher `current`
- [x] Brancher un client MCP sur ce couloir sans écraser l'install stable
- [x] Nettoyer le couloir (`remove`) ; tests hermétiques verts

## Notes

Une étiquette jetable ne doit pas pouvoir usurper un tag (préfixe réservé, ou
refus si l'étiquette ressemble à `vX.Y.Z`) — géré par l'id de couloir `dev-*`.
