---
id: "20261013221421833"
title: "mag provision — monter le projet OAuth depuis le CLI (phase A)"
type: feature
priority: P0
product: google-mcp-multi-account
version:
epic: 0017
status: shipped
ready:
pr: "local (302efa4)"
created: 2026-10-13
---

## En clair

Un nouvel arrivant doit pouvoir monter son projet OAuth **depuis `mag`**, sans découvrir
qu'il existe un script caché. On ajoute la commande `mag provision`, qui lance le
provisioning guidé (projet GCP, APIs, écran de consentement, client OAuth, publication).
C'est un **alias mince** : le moteur reste `scripts/provision-gcp.sh`, déjà testé et
idempotent, que l'admin web appelle déjà. Premier morceau de l'épic « onboarding piloté par
le CLI mag ».

## Contexte / Problème

Aujourd'hui, pour démarrer, il faut lancer `./scripts/provision-gcp.sh` — un script à part,
hors `mag`. Un nouvel arrivant ne le devine pas. Le principe directeur du projet est la
parité **CLI ⊇ admin** : tout ce que fait l'admin doit se faire sous `mag`. L'admin shelle
déjà ce script (`/api/setup`, `/api/sync-iam`) ; le CLI, lui, ne l'expose pas encore.

Cadrage et décision d'architecture : voir
[Onboarding piloté par le CLI mag — parité CLI ⊇ admin](../20261013215354286_onboarding-pilote-cli-mag-parite-admin.md).
Décision 1 retenue : alias mince, pas un wrapper qui réécrit la logique (le moteur marche,
on ne le forke pas).

## Proposition

- Ajouter la sous-commande `mag provision` au dispatch de `bin/mag`.
- Elle délègue au script en passant tous les arguments tels quels :
  - `mag provision` — flow guidé complet (phase A) ;
  - `mag provision status [--json]` — état des lieux (lecture seule) ;
  - `mag provision sync-iam [--yes]` — accorder le rôle IAM manquant.
- Mettre à jour l'usage en tête de `bin/mag`.
- Le moteur (`scripts/provision-gcp.sh`) ne bouge pas.

## Critères d'acceptation

- [x] `mag provision --help` affiche l'usage du provisioning (route vers le script).
- [x] `mag provision status`, `mag provision sync-iam` passent leurs arguments au script.
- [x] L'usage en tête de `mag` liste `provision` avant `add`.
- [x] Alias mince : aucune logique de provisioning dupliquée dans `bin/mag`.
- [x] Test hermétique : `mag provision` route vers `scripts/provision-gcp.sh`.

## Comment vérifier

```bash
mag provision --help      # doit afficher l'en-tête de provision-gcp.sh
mag provision status      # état des lieux (lecture seule)
./scripts/test.sh         # le test « mag provision route vers … » est vert
```

## Notes

- Alias mince volontaire (décision 1 de la fiche de cadrage). Les increments suivants —
  `setup_status` en étapes ordonnées, puis le test de parité admin ↔ CLI — sont des fiches
  filles distinctes.
- Livraison locale (pas de PR, dépôt piloté sans GitHub pour l'instant).
