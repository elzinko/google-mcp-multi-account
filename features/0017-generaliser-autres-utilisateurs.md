---
id: 0017
title: Généraliser le projet à d'autres utilisateurs que l'auteur
type: epic
priority: P2
version:
epic:
status: idea
ready:
pr:
created: 2026-07-24
---

## Contexte / Problème

La critique du projet (session du 2026-07-24) a établi que la **population
d'utilisateurs effective est 1** : l'auteur. Chaque couche verrouille l'adoption
par quelqu'un d'autre :

- **macOS Apple Silicon câblé en dur** — Trousseau, Touch ID, `/opt/homebrew`,
  `stat -f`, `open` : hors macOS, non fonctionnel **et non annoncé** (→ 0018).
- **Documentation 100 % française** — rédhibitoire pour une audience GitHub (→ 0019).
- **Installation par `git clone` + symlink codé en dur + édition manuelle de
  config** — pas de release, pas de packaging (→ 0020).
- **Couverture MCP étroite** — 9 tools dont 3 méta ; Calendar/Docs/Sheets/Tasks
  inaccessibles depuis un client sans shell : friction d'install maximale pour la
  fonctionnalité la plus pauvre du marché (→ 0021).

Décision produit (Thomas) : « pas forcément que pour moi ». Donc : acter macOS
comme plateforme actuelle (tag README, fait), et ouvrir un axe roadmap pour lever
les barrières d'adoption.

## Proposition

Épic parapluie qui **regroupe** les fiches levant les barrières d'accès. Aucun
travail propre : il coordonne 0018 (cross-platform), 0019 (doc EN), 0020
(packaging), 0021 (couverture MCP). Jamais tirable — on tire ses enfants.

## Critères d'acceptation

- [ ] Un utilisateur **non-auteur**, sur Linux **ou** Intel, en **anglais**, peut
      installer et utiliser le serveur MCP **sans éditer le code** ni un chemin.
- [ ] Le README n'affirme plus de généricité que le produit ne tient pas.
- [ ] Enfants livrés : 0018, 0019, 0020 (0021 = confort, hors chemin critique).

## Notes

- Priorité **proposée P2** — à recadrer (voir aussi la tension stratégique : le
  différenciateur multi-comptes vit en sursis, cf. critique « obsolescence »).
- Prérequis de valeur : la barrière de sécurité reste conventionnelle tant que
  [[0003]] (vault) n'est pas fait — généraliser sans fermer ce trou expose
  d'autres utilisateurs au même contournement. Séquencer 0003 **avant** une vraie
  diffusion.
