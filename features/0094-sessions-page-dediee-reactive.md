---
id: 0094
title: Panneau Sessions LLM — page dédiée réactive et plus lisible (au lieu d'une modale)
type: feature
priority: P2
product: google-mcp-multi-account
version:
epic: 0060
status: in-progress
ready: 2026-08-30
pr:
created: 2026-08-30
---

## En clair

Le panneau qui liste les sessions LLM existe, mais il vit dans une **modale** trop à
l'étroit et il ne se met pas à jour tout seul. On veut le sortir en **page dédiée**, avec
plus de place, un **rafraîchissement automatique** (les sessions apparaissent/expirent en
temps réel sans cliquer « Rafraîchir »), et une présentation plus soignée.

Demande PO du 2026-08-30, après avoir vu le panneau actuel (capture fournie) : « il me
faudrait une UI plus aboutie… plutôt qu'une modale, une page complète pour avoir plus de
place ».

## État actuel (ce qui existe déjà)

- Backend : lecture du registre `.sessions/` dans `listSessions()` — `admin/server.js:494`
  (capacités par session : unlocks + zones Drive avec minutes restantes).
- Routes API : `GET /api/sessions`, `POST /api/sessions/<sid>/unlock|grant|revoke-descendants|close`
  — `admin/server.js:683`.
- Front : modale `dSessions`, rendu `renderSessions()` — `admin/index.html:1148`,
  rechargement **manuel** via `refreshSessions()` — `admin/index.html:1137`.

Limites constatées : place réduite (modale scrollable), pas de temps réel (il faut
cliquer « Rafraîchir »), densité visuelle perfectible (cartes empilées).

## Ce qu'on veut

1. **Page dédiée** « Sessions » (pas une modale) : plus de largeur, mise en page aérée,
   les cartes de session peuvent s'étaler (grille), place pour afficher parent/enfants,
   client, capacités et TTL sans scroll à l'étroit.
2. **Réactif** : la liste se met à jour seule. Deux pistes à trancher au grooming —
   - simple : polling léger (ex. toutes les 3–5 s) tant que la page est ouverte ;
   - mieux : flux serveur (SSE) poussé par l'admin sur changement du registre `.sessions/`.
   Recommandation : commencer par le **polling** (peu de code, suffisant), garder SSE en
   option si le rendu « saute ».
3. **Plus joli** : hiérarchie parent/enfant lisible, TTL en compte à rebours clair,
   capacités en pastilles cohérentes avec le reste de l'admin, actions (Unlock, Zone
   Drive, Révoquer enfants, Purger) bien visibles. Respecter la règle **no-layout-shift**
   de l'UX admin (pas de saut à chaque refresh).

## Hors périmètre

- Pas de nouveau modèle de droits : on réutilise l'API `/api/sessions/*` existante.
- Pas de refonte des autres panneaux (comptes, policy, setup) — cette fiche = **Sessions**
  seulement.

## Definition of Done (proposée)

- Un point d'entrée « Sessions » ouvre une **page** (pas la modale), avec plus de place.
- La liste se **rafraîchit automatiquement** ; une session ouverte/fermée par un agent
  apparaît/disparaît sans action manuelle.
- Les capacités, le TTL et la hiérarchie sont lisibles d'un coup d'œil ; pas de layout
  shift au refresh.
- Les actions Unlock / Zone Drive / Révoquer enfants / Purger fonctionnent comme avant.
- Priorité P2 proposée (confort, pas bloquant) — à confirmer côté PO.
