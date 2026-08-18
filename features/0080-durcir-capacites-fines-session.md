---
id: 0080
title: Durcir la couche capacités fines de session (suite revue Codex #110)
type: feature
priority: P1
version:
epic: 0082
status: todo
ready:
pr:
created: 2026-08-16
---

## Contexte / Problème

L'implémentation de la Phase A ([0076](0076-droits-par-session-phase-a.md), PR #110)
livre les capacités fines de session (service × opération × ressource). La revue
Codex de #110 a relevé **trois raffinements non bloquants**, différés ici pour ne
pas retarder le merge du cœur — le P0 (intersection Drive fail-open) et le P1
(« session nue = deny-all ») étant, eux, traités **dans** #110.

## Proposition

1. **Ressource pour les services non-Drive** — `scripts/policy-check.py` appelle
   `check_session_caps` avec une ressource **vide** hors du chemin Drive. Dériver et
   passer la ressource propre au service (Gmail `labelId`, Calendar `calendarId`, …)
   pour que la granularité ressource annoncée marche aussi hors Drive : une capacité
   `calendar:read:cal123` doit autoriser `calendar events list calendarId=cal123` et
   refuser un autre agenda.
2. **Figer les capacités déléguées à la création** — l'héritage
   (`gateway/sessions.py`, `active_capabilities`) résout les capacités d'un enfant sur
   l'état **live** du parent : un octroi signé accordé au parent *après* la création
   de l'enfant s'expose passivement à cet enfant. Figer (snapshot) les capacités
   héritées au moment de la création de la sous-session (le payload signé ne nommait
   que le parent).
3. **Aligner la catégorie d'audit sur l'autorisation** — `gateway/usage.py`
   (`infer_call`) journalise `create` là où l'autorisation classe `drafts` (Gmail) ou
   `share` (Drive permissions). Utiliser la même catégorisation *service-aware* que
   `policy-check.py`, pour que le triplet d'audit identifie la capacité qui a
   réellement autorisé l'appel.

## Critères d'acceptation

- [ ] Une capacité `<service>:<op>:<ressource>` **non-Drive** (Gmail label, Calendar
      agenda) autorise l'op sur cette ressource et **refuse** les autres — testé.
- [ ] Les capacités d'une sous-session sont **figées à sa création** ; un octroi
      ultérieur au parent **n'élargit pas** l'enfant existant — testé.
- [ ] L'audit des appels réussis utilise la **catégorie d'autorisation** (`drafts`,
      `share`, …), pas le seul nom de méthode — testé.
- [ ] `./scripts/test.sh` vert.

## Notes

- Suite de la revue Codex de la PR #110 (findings P2). Parent :
  [0076](0076-droits-par-session-phase-a.md) /
  [ADR-0007](../docs/adr/ADR-0007-droits-par-session.md).
