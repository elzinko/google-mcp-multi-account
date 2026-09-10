---
id: 20260910160500000
title: Poll de fond profils/sessions — le piloter par le registre de route (éviter les fetch inutiles)
type: refactor
priority: P3
product: google-mcp-multi-account
version:
epic: 0060
status: idea
ready:
pr:
created: 2026-09-10
---

## En clair

Le micro-routeur (fiche 0098) unifie les polls de **route** (Sessions, Journal…). Mais un
poll de **fond** tourne en plus, toutes les 8 s, sur **toutes** les vues : il rafraîchit les
profils **et** les sessions (`refresh()` → `/api/profiles` + `/api/sessions`). Sur une vue qui
n'a pas besoin des compteurs de sessions (ex. Journal), on fait donc un appel `/api/sessions`
pour rien. Idée : intégrer ce poll de fond au registre de route pour ne fetch que ce dont la
vue active a besoin.

Origine : revue Codex de la PR #139 (finding P2), déclinée dans cette PR car hors scope 0098
(« comportement inchangé »). Capturée ici pour ne pas la perdre.

## Contexte / problème

- `refresh()` (`admin/index.html`) fetch `/api/profiles` **et** `/api/sessions` à chaque tick,
  et tourne via `setInterval(refresh, 8000)` **indépendamment de la route** — hors du registre
  `ROUTES` introduit par 0098.
- Les compteurs de sessions par compte (fiche 0106) ne sont utiles que sur la page **Comptes**
  (liste). Sur Journal, ou dans une modale, le fetch `/api/sessions` de fond est **redondant**.
- Ce n'est pas un bug : les données restent justes, c'est un gaspillage réseau modéré.

## Proposition

- Déclarer le besoin « compteurs de sessions » comme une donnée **de la route liste** (et
  éventuellement détail), pas un fetch global inconditionnel.
- Faire piloter le rafraîchissement profils/sessions par le registre `ROUTES` (ou un « poll de
  fond » explicitement déclaré par les routes qui en ont besoin), pour couper le fetch
  `/api/sessions` là où aucune vue ne l'exploite.
- Garder le rafraîchissement des profils là où il est nécessaire (état de connexion, cadenas).

## Critères d'acceptation

- [ ] Sur la route Journal (au repos), **aucun** appel `/api/sessions` n'est émis par le poll de
      fond (vérifiable au panneau réseau).
- [ ] Les compteurs de sessions de la page Comptes restent frais (auto-refresh inchangé).
- [ ] Comportement fonctionnel inchangé ailleurs (pas de régression de l'état de connexion / cadenas).

## Comment vérifier

Ouvrir l'admin, aller sur Journal, observer le réseau : plus de `/api/sessions` périodique.
Revenir sur Comptes : les compteurs « N session(s) » se mettent toujours à jour tout seuls.
