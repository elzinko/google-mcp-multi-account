---
id: 0099
title: Sessions — tranche pilote du design system (cartes régulières + tri + bascule liste/vignettes)
type: feature
priority: P1
product: google-mcp-multi-account
version:
epic: 0060
status: todo
ready:
pr:
created: 2026-08-30
---

## En clair

La page Sessions devient la **première application** du design system : cartes de taille
régulière, un **tri** (par client, par dernière activité, par nombre de capacités), et une
**bascule liste / vignettes** façon Finder, avec le choix mémorisé. C'est la tranche qui
prouve tout le système avant de l'appliquer aux écrans denses.

Référence : [`docs/design/design-system-admin.md`](../docs/design/design-system-admin.md) §3 et §6. Fait suite à la fiche 0094 (page dédiée réactive, livrée).

## Contexte / problème

La page Sessions existe (fiche 0094) mais : les cartes sont de hauteurs inégales (pas de
`min-height`, actions non ancrées), il n'y a **ni tri ni bascule de vue**, et jusqu'à 4
boutons d'action débordent sur carte étroite. Le tri par projet est **exclu** ici : la
session ne mémorise pas encore son projet (fiche séparée à venir).

## Proposition

- Cartes régulières : `min-height`, `sess-actions { margin-top:auto }` → alignement.
- Contrôle segmenté **liste / vignettes** (distinct des onglets), état persisté en
  `localStorage` (modèle « Vue dense » du journal). Vignettes = grille ; liste = rangée
  dense par session.
- **Tri** : client, dernière activité, nombre de capacités.
- Débordement d'actions : action principale + menu pour le reste quand > 2.

## Critères d'acceptation

- [ ] Toutes les cartes ont la même hauteur ; actions ancrées en bas.
- [ ] Bascule liste/vignettes fonctionnelle, choix mémorisé entre visites.
- [ ] Tri par client / activité / capacités.
- [ ] Auto-refresh (fiche 0094) conservé, sans saut visuel (no-layout-shift).
- [ ] Rendu clair ET sombre corrects.

## Comment vérifier

Ouvrir Sessions avec plusieurs sessions de test : basculer liste↔vignettes (le choix
persiste après rechargement), trier, vérifier l'alignement des cartes et l'absence de saut
au rafraîchissement.
