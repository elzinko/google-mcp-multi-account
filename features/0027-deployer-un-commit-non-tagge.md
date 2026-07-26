---
id: 0027
title: Déployer un commit non taggé pour essayer une PR (couloir jetable)
type: feature
priority: P2
version:
epic:
status: idea
ready:
pr:
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

## Critères d'acceptation

- [ ] À groomer.

## Notes

Une étiquette jetable ne doit pas pouvoir usurper un tag (préfixe réservé, ou
refus si l'étiquette ressemble à `vX.Y.Z`).
