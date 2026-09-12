---
id: 0071
title: GitHub metadata — description, homepage, topics + badges
type: chore
priority: P2
version: v0.4.0
epic: 0060
status: shipped
ready:
pr:
created: 2026-07-29
---

> **Livré (2026-08-08).** Réconciliation : les métadonnées GitHub sont posées et
> alignées. Vérifié via `gh repo view` — description (multi-account, default-deny,
> human-in-the-loop, macOS), homepage = site de doc en ligne, **17 topics** dont
> `mcp`, `model-context-protocol`, `multi-account`, `local-first`,
> `human-in-the-loop`, `least-privilege` ; badges CI / Release / License / Platform
> dans le README. Livraison hors PR (réglages du dépôt), d'où `pr:` vide.

## Contexte / Problème

Métadonnées GitHub (description, homepage, topics, badges) pas alignées sur
le positionnement multi-account + policy + human-in-the-loop + local-first.

## Proposition

Mettre à jour description, homepage (si docs), topics, cohérence des badges.

## Critères d'acceptation

- [ ] Voir issue GitHub (source de vérité des critères)

## Notes

- **Issue** : [#72](https://github.com/elzinko/google-mcp-multi-account/issues/72)
- **Épic** : [[0060]] · [#59](https://github.com/elzinko/google-mcp-multi-account/issues/59)
- **Project** : [v0.4.0](https://github.com/users/elzinko/projects/2) · **Milestone** : [v0.4.0](https://github.com/elzinko/google-mcp-multi-account/milestone/1)
