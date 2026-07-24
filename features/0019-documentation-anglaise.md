---
id: 0019
title: Documentation anglaise — ouvrir le projet à une audience non francophone
type: feature
priority: P2
version:
epic: 0017
status: idea
ready:
pr:
created: 2026-07-24
---

## Contexte / Problème

Toute la documentation (README, `docs/`, messages) est en **français**. Pour un
projet open-source sur GitHub, c'est une barrière d'entrée forte : la quasi-
totalité de l'audience potentielle ne lira pas le README.

## Proposition

- **README anglais** à la racine (source de vérité), version française en regard
  (`README.fr.md`) — ou bascule EN par défaut + lien FR.
- Traduire les docs d'accueil clés : `docs/mcp-setup.md`, `docs/setup-oauth.md`,
  `docs/usage.md`.
- **Décider** pour les messages CLI/erreurs de `gwsa` : rester FR, passer EN, ou
  bilingue — trancher à l'anglais si on vise l'adoption externe.

## Critères d'acceptation

- [ ] README anglais à la racine, à jour et cohérent avec la version FR.
- [ ] Docs de setup (OAuth, MCP, usage) disponibles en anglais.
- [ ] Politique de langue des messages CLI décidée et appliquée.

## Notes

Ne pas traduire mécaniquement les 4 diagrammes ni les ADR (coût > valeur au
départ) : prioriser le chemin d'onboarding. Voir épic [[0017]].
