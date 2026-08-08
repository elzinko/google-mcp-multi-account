---
id: 0069
title: Docs in-app — rework orientation utilisateur
type: feature
priority: P2
version: v0.4.0
epic: 0060
status: todo
ready:
pr:
created: 2026-07-29
---

> **Maintenue — clôture prématurée annulée (2026-08-08, revue Codex).** La doc
> in-app existe **encore sur `main`** : `admin/index.html` charge `mermaid.min.js`
> et appelle `/api/doc`, servi par `admin/server.js`. Son retrait
> ([#85](https://github.com/elzinko/google-mcp-multi-account/pull/85)) a été mergé
> dans la branche de l'épic (`feat/0060-admin-ux-refresh`, draft #84), **pas dans
> `main`**. Donc : la fiche reste ouverte tant que #84 n'est pas mergée. À ce
> moment-là, le retrait + le site en ligne ([[0072]] / #79) la rendront obsolète —
> à re-clôturer alors. Ne pas re-shipper avant.

## Contexte / Problème

La documentation in-app mélange parcours utilisateur et contenu
dev/architecte ; onboarding perçu comme peu « pro produit ».

## Proposition

Rework orienté user ; contenu dev/architecte en section dédiée (ou
redirection vers la doc complète).

## Critères d'acceptation

- [ ] Voir issue GitHub (source de vérité des critères)

## Notes

- **Issue** : [#69](https://github.com/elzinko/google-mcp-multi-account/issues/69)
- **Épic** : [[0060]] · [#59](https://github.com/elzinko/google-mcp-multi-account/issues/59)
- **Project** : [v0.4.0](https://github.com/users/elzinko/projects/2) · **Milestone** : [v0.4.0](https://github.com/elzinko/google-mcp-multi-account/milestone/1)
