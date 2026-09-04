---
id: 0070
title: README — quickstart + usage par persona + permissions + contribution
type: feature
priority: P2
version: v0.4.0
epic: 0060
status: todo
ready: 2026-09-04
pr:
created: 2026-07-29
---

## En clair

Le rebrand #58 a déjà refait le gros du README (quickstart, permissions, badges, sécurité).
Restent **deux manques ciblés** : un usage **par persona** (utilisateur quotidien, admin/PO,
contributeur) et une vraie section **Contribution** (setup dev, tests, conventions de commit).
Cette fiche livre juste ces deux ajouts.

## Contexte / Problème

Le README n'est pas assez orienté résultat pour un onboarding rapide
(quickstart, personas, permissions/élicitation, contribution).

## Proposition

Restructurer : quickstart 3–5 min, usage par persona, permissions IAM /
élicitation, section contribution ; conserver badges et posture sécurité.

## Critères d'acceptation

> **Réconciliation (2026-08-08).** Le rebrand #58 a déjà refait le README :
> quickstart, permissions / human-in-the-loop, badges + posture sécurité. Restent
> deux manques ciblés.

- [x] Quickstart + permissions/élicitation + badges/sécurité — livré #58.
- [ ] **Usage par persona** (≈3 : utilisateur quotidien, admin/PO, contributeur).
- [ ] Section **Contribution** explicite (setup dev, tests, conventions de
      commit) — au-delà du bloc « Development » actuel.
- Source des critères : [issue #70](https://github.com/elzinko/google-mcp-multi-account/issues/70).

## Comment vérifier

Ouvrir le README : une section **usage par persona** (les 3 profils) et une section
**Contribution** (setup dev, `./scripts/test.sh`, conventions de commit) sont présentes,
au-delà du bloc « Development » actuel. Le quickstart et la posture sécurité (livrés #58)
restent intacts.

## Notes

- **Issue** : [#70](https://github.com/elzinko/google-mcp-multi-account/issues/70)
- **Épic** : [[0060]] · [#59](https://github.com/elzinko/google-mcp-multi-account/issues/59)
- **Project** : [v0.4.0](https://github.com/users/elzinko/projects/2) · **Milestone** : [v0.4.0](https://github.com/elzinko/google-mcp-multi-account/milestone/1)
