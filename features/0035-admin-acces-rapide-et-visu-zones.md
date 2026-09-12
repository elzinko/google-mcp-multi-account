---
id: 0035
title: Accès rapide à l'admin + visualisation des zones (icône barre de menus ?)
type: feature
priority: P2
version:
epic:
status: idea
ready:
pr:
created: 2026-07-27
---

> **Gardée mais parquée (décision PO 2026-09-04).** Utile, mais **pas prioritaire** pour l'instant.
> **Prérequis** : l'admin doit d'abord pouvoir démarrer **seul** — en app ou en service —
> indépendamment de `mag admin`. Sans ça, l'icône n'a rien à piloter au repos. Réserve assumée :
> c'est du natif macOS (barre de menus), que le projet évite ; à revisiter quand le prérequis
> « admin autonome » existe.

## Contexte / Problème

Pour voir l'état des accès (profils verrouillés, zones actives), il faut se
souvenir de `mag admin`, l'exécuter, attendre l'ouverture du navigateur. Rien
ne signale, au repos, qu'un profil est déverrouillé ou qu'une zone est ouverte.

Aujourd'hui :
- `mag admin` démarre le serveur **et** ouvre `http://127.0.0.1:4877` tout seul.
- L'admin **affiche déjà** les zones (permanentes + temporaires, avec compte à
  rebours) — la donnée est là, c'est l'accès qui manque.

Demandé le 2026-07-27 : un point d'accès permanent, type **icône dans la barre
de menus macOS**, pour ouvrir l'admin en un clic et voir d'un coup d'œil ce qui
est ouvert.

## Proposition (à cadrer)

- Une icône barre de menus (menu bar / status item) qui :
  - ouvre l'admin en un clic ;
  - montre au repos un résumé : combien de profils déverrouillés, combien de
    zones actives (badge/pastille quand quelque chose est ouvert).
- Piste technique : petit agent `launchd` + utilitaire status-bar (Swift natif,
  ou `rumps` en Python). À évaluer contre la contrainte « zéro dépendance
  lourde » du projet.
- Alternative légère si l'icône est trop coûteuse : `mag admin` reste le point
  d'entrée, + un favori navigateur documenté.

## Critères d'acceptation

- [ ] À groomer.

## Notes

- Ne pas dupliquer l'affichage des zones : l'admin le fait déjà, l'icône ne
  fait que **mener** à l'admin et résumer l'état.
- Contrainte macOS assumée (barre de menus) — cohérent avec l'épic 0017
  (cross-platform) qui traitera le reste plus tard.
