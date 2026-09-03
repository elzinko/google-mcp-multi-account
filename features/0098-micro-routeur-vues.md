---
id: 0098
title: Micro-routeur — formaliser les vues (pages vs modales), un seul registre de poll
type: refactor
priority: P1
product: google-mcp-multi-account
version:
epic: 0060
status: todo
ready: 2026-09-03
pr:
created: 2026-08-30
---

## En clair

Aujourd'hui « rendre » et « naviguer » sont mélangés : les fonctions de rendu réécrivent
l'état de vue `VIEW`, et il y a plusieurs boucles de rafraîchissement en parallèle. On
formalise ça avec un petit routeur `go()` et un registre de poll unique. Objectif :
comportement identique, mais une base saine pour ajouter des pages sans bricoler.

Référence : ADR-0010 (brique 3).

## Contexte / problème

`VIEW = {mode, alias}` est réassigné *dans* les `render*()` (`renderList`, `renderDetail`) →
rendre a l'effet de bord de naviguer. **Trois boucles de poll séparées** tournent en parallèle,
chacune son `setInterval` : `LAST` (profils), `SESS_LAST` (sessions), `JRN_LAST` (journal) ;
`rerender` garde un early-return codé à la main pour sessions/journal. Une **amorce partielle**
existe déjà (`syncChrome` / `syncNav` / `clearPageTimers`) : le refactor s'appuie dessus plutôt
que de repartir de zéro. Ajouter une page oblige encore à toucher plusieurs endroits.

## Proposition

- Extraire `go(mode, params)` : fixe `VIEW`, appelle `syncChrome`, dispatche vers le bon
  `render*`. Les `render*` **cessent** de muter `VIEW`.
- Un registre de poll par route remplace les boucles ad hoc (`LAST`, `SESS_LAST`, timer 1 s).
- Règle documentée : une surface est une **page** si elle a son propre flux de données / sa
  cadence ; sinon une **modale**. Pages = liste, détail, sessions (Setup candidat ultérieur).

## Critères d'acceptation

- [ ] Les `render*` ne réassignent plus `VIEW`.
- [ ] Une seule mécanique de poll pilotée par la route active.
- [ ] Navigation, retour, Échap, et le no-layout-shift de Sessions inchangés.

## Comment vérifier

Naviguer liste ↔ détail ↔ sessions, tester Échap et le retour ; le poll ne réécrit pas une
vue inactive. Le décompte du cadenas et l'auto-refresh Sessions fonctionnent comme avant.
