---
id: "20261013221927791"
title: "setup_status en étapes ordonnées — rendu checklist terminal + admin"
type: feature
priority: P1
product: google-mcp-multi-account
version:
epic: 0017
status: ready
ready:
pr:
created: 2026-10-13
---

## En clair

Aujourd'hui `setup_status` dit l'état (projet, publication, IAM) et propose des
`next_actions`, mais pas « tu es à l'étape 3 sur 6, voici la suivante ». On l'étend pour
émettre une **liste d'étapes ordonnées** avec, par étape, son statut (fait / en cours / à
faire) et son action. Les deux faces la **rendent** : `mag provision` en checklist dans le
terminal, l'admin en JSON. Increment n°2 de l'épic, après
[mag provision](done/20261013221421833_mag-provision-alias-cli.md).

## Contexte / Problème

`setup_status` reste la **source d'état unique** (ADR-0002, lecture seule). Il calcule déjà
projet, publication, `client_secret`, IAM par compte, et des `next_actions`. Mais un nouvel
arrivant ne voit pas d'un coup d'œil *où il en est* dans le fil (phase A : consentement,
client OAuth, publication). La maquette (`docs/mockups/onboarding-cli.html`) montre la cible :
une checklist ordonnée, identique au terminal et dans l'admin.

Cadrage : [Onboarding piloté par le CLI mag](20261013215354286_onboarding-pilote-cli-mag-parite-admin.md),
décision 2 (la machine d'état vit dans `setup_status`, le script reste l'exécuteur).

## Proposition

- Étendre `setup_status()` pour émettre un tableau `steps` ordonné : `{key, title, state:
  done|now|todo, action}` couvrant la phase A (consentement, client OAuth, publication) et la
  phase B (connecter un compte, accès IAM).
- `setup_status` reste **en lecture seule** : il décrit et propose, il n'exécute rien.
- Rendu terminal : `mag provision status` affiche la checklist ordonnée.
- Rendu admin : le panneau 🩺 lit le même `steps`.

## Critères d'acceptation

- [x] `setup_status` expose `steps` ordonné (clé, titre, état, action) pour les phases A et B.
- [x] `mag provision status` rend la checklist dans le terminal.
- [x] L'admin rend les mêmes étapes depuis le même JSON (aucun calcul d'étapes côté JS).
- [x] `setup_status` reste lecture seule (aucune mutation).
- [x] Tests : l'ordre et les états des étapes sont vérifiés sur un `GWSA_ROOT` de fixture.

## Comment vérifier

```bash
mag provision status            # checklist ordonnée, étape courante mise en évidence
mag provision status --json     # contient un tableau "steps" ordonné
./scripts/test.sh               # tests d'ordre/état des étapes verts
```

## Notes

- Dépend de [mag provision](done/20261013221421833_mag-provision-alias-cli.md) (livré).
- La cible visuelle est la maquette `docs/mockups/onboarding-cli.html`.
