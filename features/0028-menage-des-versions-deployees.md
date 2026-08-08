---
id: 0028
title: Ménage des versions déployées (+ CHANGELOG et releases GitHub)
type: chore
priority: P3
version:
epic:
status: idea
ready:
pr:
created: 2026-07-26
---

## Contexte / Problème

`~/.local/share/google-mcp/` grossit à chaque déploiement et rien ne purge.
Le rollback a besoin d'un historique court, pas de tout l'historique.

Côté publication, les tags sont déjà la source de vérité, mais il n'existe ni
`CHANGELOG.md` ni release GitHub : impossible de savoir ce qu'apporte une
version sans lire le journal git.

## Proposition

- `deploy-local.sh --prune [n]` : garde les `n` dernières versions plus
  `current`, jamais celle en service.
- `CHANGELOG.md` dérivé des conventional commits, une section par tag.
- `gh release create <tag>` à partir de cette section.

## Critères d'acceptation

> **Réconciliation (2026-08-08).** 2/3 déjà faits : `CHANGELOG.md` existe et les
> **releases GitHub** sont publiées (v0.3.0, v0.4.0). Reste **un seul** item.

- [x] `CHANGELOG.md` (une section par tag).
- [x] Releases GitHub (`gh release`) — v0.3.0, v0.4.0 publiées.
- [ ] `deploy-local.sh --prune [n]` : garder les `n` dernières versions +
      `current`, jamais celle en service (aucun `--prune` aujourd'hui).

## Notes

Confort, pas correctif. À faire après les fiches 0025 et 0026.
