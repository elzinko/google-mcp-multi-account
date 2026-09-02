---
id: 0102
title: Journal en page dédiée — filtres + journal par session (virage monitoring)
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

Le journal est aujourd'hui une modale illisible. On le sort en **page dédiée** (comme
Sessions), avec des **filtres** (par compte, par session, par type d'action, par date) et
un **lien « journal » sur chaque session** qui ouvre le journal déjà filtré sur elle.

C'est le virage assumé : l'admin devient un **outil de monitoring** de ce que font les
agents, pas seulement un gestionnaire de comptes.

Référence : design system [`docs/design/design-system-admin.md`](../docs/design/design-system-admin.md) (§ bascule liste, callout). Voisin de 0099 (Sessions en page).

## Contexte / problème

Le journal vit dans la modale `dLog` (`admin/index.html`), à l'étroit et sans filtre :
on ne peut pas isoler une session ni un compte. Or **le journal enregistre déjà le
`session_id` de chaque action** (`scripts/log-usage.py` pose `entry["session_id"]` ;
`broker_server.py` loggue avec `session_id`). La matière pour un journal par session
existe donc — il manque l'interface.

## Proposition

- **Page dédiée** « Journal » (même bascule de vue que Sessions ; sortir de la modale).
- **Filtres** : compte (alias), session (session_id), type d'action (service/opération),
  fenêtre de temps. Combinables. Conserver la « Vue dense » existante.
- **Journal par session** : sur chaque carte/rangée de session, une action « Journal »
  ouvre la page Journal pré-filtrée sur `session_id`.
- Réutiliser les composants du design system (page, filtres = contrôles segmentés/selects,
  callout d'aide).

## Critères d'acceptation

- [ ] Le journal s'ouvre en page (plus la modale), lisible, avec plus de place.
- [ ] Filtres compte / session / type / date, combinables, sans rechargement.
- [ ] Depuis une session, un clic ouvre son journal filtré.
- [ ] Le tri/filtre ne casse pas le no-layout-shift (rerender maîtrisé).

## Comment vérifier

Générer quelques entrées de journal (actions via un client MCP de test), ouvrir la page
Journal, filtrer par session et par compte, et vérifier que le lien « Journal » d'une
session ouvre bien le journal filtré sur elle.
