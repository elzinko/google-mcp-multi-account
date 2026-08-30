---
id: 0100
title: Déploiement du design system écran par écran + passe contraste AA
type: feature
priority: P2
product: google-mcp-multi-account
version:
epic: 0060
status: todo
ready:
pr:
created: 2026-08-30
---

## En clair

Une fois les fondations et les composants posés, on applique le système aux écrans
restants, un par un, et on finit par une passe de contraste. Chaque écran est une
sous-étape livrable seule.

Référence : [`docs/design/design-system-admin.md`](../docs/design/design-system-admin.md) §5. Dépend de 0095, 0096, 0097.

## Contexte / problème

Après la tranche pilote Sessions, les autres écrans restent à migrer : détail, policy,
liste des comptes, dev, setup. Quelques défauts UX à corriger au passage, plus des points
de contraste (le gris `--mut` passe AA de justesse en clair ; `.b-mut` invisible sur `--bg`).

## Proposition

- **Détail** : fusionner les « Configurer… » répétés (une modale unique) en un seul bouton
  de section.
- **Policy** : préréglages en segmenté (fin des faux onglets) ; notes en callouts ;
  repenser la modale de zones imbriquée (panneau inline plutôt qu'empilement de dialogues).
- **Liste des comptes** : libellé d'état à côté du cadenas ; clarifier la double cible de clic.
- **Dev / Setup** : adopter carte + segmenté ; Setup peut devenir une page.
- **Passe contraste AA** : assombrir `--mut` clair (~`#63625d`), corriger `.b-mut` sur `--bg`,
  revérifier pastilles/badges/chips en clair et sombre.

## Critères d'acceptation

- [ ] Chaque écran migré utilise tokens + composants partagés (plus de recette locale).
- [ ] Détail : un seul bouton de configuration des droits.
- [ ] Policy : préréglages qui ne ressemblent plus à des onglets ; notes en callouts.
- [ ] Contraste AA vérifié partout, clair et sombre.

## Comment vérifier

Parcourir chaque écran migré en clair et sombre ; contrôler le contraste (`--mut`, `.b-mut`)
avec un vérificateur. Aucune régression fonctionnelle sur policy/zones.
