---
id: 0060
title: Admin UX/UI refresh + docs/README + GitHub metadata
type: epic
priority: P1
version: v0.4.0
epic:
status: shipped
ready:
pr:
created: 2026-07-29
---

## Contexte / Problème

L'admin est fonctionnelle mais trop orientée implémentation : header chargé,
texte d'aide parasite, actions destructives sans confirmation claire, journal
peu lisible, branding et docs à aligner sur un produit « user-first ».

## Proposition

Épic parapluie **v0.4.0** : refonte UX/UI admin + docs/README + métadonnées
GitHub, sans casser les garde-fous (default-deny, confirmations humaines,
strongauth). Jamais tirable — on tire les enfants.

## Critères d'acceptation

- [x] Enfants MVP livrés : 0061–0067
- [x] Enfants docs / a11y / metadata livrés : 0068–0071
- [ ] Milestone GitHub [v0.4.0](https://github.com/elzinko/google-mcp-multi-account/milestone/1) fermable — *geste GitHub humain, hors dépôt*

## Notes

- **Issue épic** : [#59](https://github.com/elzinko/google-mcp-multi-account/issues/59)
- **Project** : [google-mcp-multi-account — v0.4.0](https://github.com/users/elzinko/projects/2)
- **Milestone** : [v0.4.0](https://github.com/elzinko/google-mcp-multi-account/milestone/1)
- Détail et captures : vivre dans l'issue GitHub — cette fiche est un index.

## Clôture (réconciliation 2026-09-20)

Épic clos : ses 11 enfants (0061 → 0071) sont tous dans `features/done/`, chacun livré
par sa propre PR (référence dans chaque fiche enfant). La fiche épic était restée
`in-progress` alors que le travail était terminé. Pas de PR propre à l'épic — il est
livré par ses enfants — d'où `pr:` vide. Reste seulement le geste GitHub humain
« fermer le milestone v0.4.0 ».
