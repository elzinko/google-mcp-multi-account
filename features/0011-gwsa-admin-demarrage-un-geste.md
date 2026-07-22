---
id: 0011
title: "`gwsa admin` — démarrer/arrêter l'interface web en un geste, proposé par l'élicitation"
type: feature
priority: P2
version:
epic:
status: in-progress
ready:
pr:
created: 2026-07-22
---

## Contexte / Problème

L'interface d'admin (cockpit humain : comptes, verrous, policies, zones,
journal) se démarrait uniquement à la main (`node admin/server.js`), et rien
ne l'indiquait à l'utilisateur au moment où elle est utile — les messages
d'élicitation citaient l'URL sans dire comment la lancer. Demande PO
(2026-07-22) : que le LLM/MCP fournisse doc + commande, cliquable quand le
client le permet.

## Proposition

1. Sous-commande **`gwsa admin [stop]`** : démarre `admin/server.js` détaché
   (pid + log dans `$GWSA_ROOT`), idempotente (déjà en route → juste ouvrir
   le navigateur), `stop` propre, `admin` devient mot réservé.
2. Les **messages d'élicitation** (locked, unlock, grant) citent « démarrer :
   `gwsa admin` » à côté de l'URL — tout client LLM sait la proposer ; dans
   Claude Code, le bloc bash est cliquable (bouton Run) ; dans Desktop,
   copier-coller (pas de shell — limite assumée).
3. README + CLAUDE.md à jour.

## Critères d'acceptation

- [x] `gwsa admin` démarre (détaché, idempotent) et ouvre le navigateur ;
      `gwsa admin stop` arrête proprement ; relance sûre.
- [x] `admin` est un mot réservé (pas de profil de ce nom).
- [x] Les 3 messages d'élicitation citent la commande de démarrage.
- [x] Tests hermétiques : mot réservé, usage, stop no-op (suite 72/72).

## Notes

- Le cycle de vie reste humain : ni la gateway ni le broker ne lancent
  l'admin (décision notée en fiche 0009 — launchd possible plus tard).
