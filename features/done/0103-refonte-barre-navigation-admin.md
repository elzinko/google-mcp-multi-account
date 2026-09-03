---
id: 0103
title: Refonte de la barre de navigation de l'admin (header/menu standard)
type: feature
priority: P2
product: google-mcp-multi-account
version:
epic: 0060
status: shipped
ready:
pr: "#128"
created: 2026-08-30
---

> **Livrée — superseded par #128 (2026-09-03).** rail de navigation en trois zones (identité / nav / outils), page active marquée (`aria-current`), menu « ⋯ » accessible.

## En clair

La barre du haut (titre + badge de version + cadenas + Sessions / Journal / Doc + menu
« ⋯ ») fait « bricolée » et pas standard. On la refait proprement : une vraie barre de
navigation d'app, cohérente avec le design system, qui tienne la route quand on ajoute des
pages (Sessions, Journal…).

Référence : design system [`docs/design/design-system-admin.md`](../../docs/design/design-system-admin.md), ADR-0010 (micro-routeur). Complète le composant bouton (fiche 0097).

## Contexte / problème

Le header (`admin/index.html`) mélange un titre, un badge de version, une icône cadenas
« Tout verrouiller », trois boutons de section et un menu overflow maison. L'ensemble n'a
pas de grammaire visuelle claire (tailles, espacements, séparation identité / navigation /
actions). Avec le virage monitoring (Sessions, Journal en pages), la navigation va prendre
de l'importance et doit devenir un vrai composant.

## Proposition

- Structurer la barre en trois zones nettes : **identité** (titre + version), **navigation**
  (les pages : Comptes, Sessions, Journal…), **actions/outils** (verrou global, Doc, menu
  avancé).
- Aligner sur les tokens (espacement, typo, rayons) et le composant bouton (variantes,
  boutons-icônes avec libellé au survol, comme sur Sessions).
- Marquer la **page active** (état sélectionné) — cohérent avec le micro-routeur (0098).
- Menu « ⋯ » : soit un vrai menu standard accessible, soit dissous si peu d'items.

## Critères d'acceptation

- [ ] Barre lisible, trois zones distinctes, alignée sur le design system.
- [ ] La page active est visuellement marquée.
- [ ] Navigation cohérente entre Comptes / Sessions / Journal.
- [ ] Accessible (focus clavier, aria), clair ET sombre.

## Comment vérifier

Naviguer entre les pages : la barre reste stable, la page active est marquée, les
boutons-icônes affichent leur libellé au survol, le rendu tient en clair et sombre.
