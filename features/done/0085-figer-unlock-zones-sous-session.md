---
id: 0085
title: Figer unlock de compte + zones Drive à la création d'une sous-session (isolation complète)
type: bug
priority: P1
version:
epic: 0082
status: shipped
ready: 2026-08-18
pr: "#119"
created: 2026-08-18
---

## Contexte / Problème

Le raffinement #2 de [0080](0080-durcir-capacites-fines-session.md) fige (snapshot) les
**capacités fines** héritées (`gateway/sessions.py`, `active_capabilities`) au moment de la
création d'une sous-session : un octroi signé accordé au parent **après** n'élargit plus l'enfant.

La revue adverse de 0080 (`ezk-reviewer`, finding P1) a confirmé **empiriquement** que **les grains
les plus puissants ne sont pas figés** : `is_session_unlocked` (`gateway/sessions.py:~347`) et
`active_drive_zones` (`:~333`) remontent encore la chaîne d'ancêtres **en direct**. Donc :

- `session_unlock(parent, alpha)` **après** la création de l'enfant → `is_session_unlocked(child,
  alpha)` devient **vrai** ;
- `session_grant_drive(parent, FOLDER_X)` **après** → `FOLDER_X ∈ active_drive_zones(child)`.

C'est exactement le **passive-widening** que l'axe « droits par session » (épic
[0082](0082-droits-par-session.md)) cherche à éliminer — laissé ouvert pour les grains *les plus
puissants* (déverrouillage de compte, zones d'écriture Drive), qui sont aussi les plus sensibles.
**Pré-existant** (pas introduit par 0080) ; 0080 l'a rendu visible en figeant les capacités fines à
côté, et son docstring a été resserré pour ne pas sur-promettre.

## Proposition

Figer (snapshot) **au moment de la création de la sous-session**, sur le même patron que le snapshot
d'`active_capabilities` (copie **par valeur**, zéro aliasing d'objet mutable) :

- l'état d'`unlock` hérité (le payload signé de création ne nommait que le parent) ;
- les zones Drive héritées.

Un `unlock`/`grant` ultérieur du parent **n'élargit pas** un enfant déjà créé. Alternative à peser
et à trancher explicitement : justifier une exception (héritage *vivant* intentionnel pour ces
grains) — mais **par défaut, l'isolation prime** (cohérence avec l'objectif de l'épic).

## Critères d'acceptation

- [ ] Parent + enfant créés, **puis** `session_unlock(parent, alpha)` → `is_session_unlocked(child,
      alpha)` reste **faux** — testé (positif + négatif).
- [ ] Parent + enfant créés, **puis** `session_grant_drive(parent, FOLDER_X)` → `FOLDER_X ∉
      active_drive_zones(child)` — testé.
- [ ] Non-régression : un enfant hérite bien de l'état **au moment de sa création** ; la révocation
      et le nettoyage côté parent restent corrects.
- [ ] `./scripts/test.sh` vert.

## Notes

- Révélé par la revue adverse `ezk-reviewer` de la feature 0080 (finding **P1**, hors périmètre
  littéral de 0080 qui ne visait qu'`active_capabilities`). Parent :
  [0082](0082-droits-par-session.md) / [ADR-0007](../docs/adr/ADR-0007-droits-par-session.md).
- Fiche sœur de [0080](0080-durcir-capacites-fines-session.md) — même couche session, classe
  « durcissements différés d'une revue ».
