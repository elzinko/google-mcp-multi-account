---
id: 0012
title: Panneau « Santé du setup » + bouton « Réparer l'accès IAM » dans l'admin
type: feature
priority: P1
version:
epic:
status: shipped
ready:
pr: "#14"
created: 2026-07-22
---

## Contexte / Problème

Réparer l'accès IAM d'un compte (`mw` en dérive) n'était possible qu'en
terminal (`provision-gcp.sh sync-iam`). L'utilisateur (2026-07-22) : n'est-ce
pas faisable **visuellement**, par un bouton, **sans enfreindre la sécurité** ?

Clarification du modèle (importante) : la frontière de l'ADR-0001 porte sur
**qui agit**, pas sur *shell vs bouton*. Le **MCP** (LLM, stdio, sans réseau ni
shell) ne doit jamais muter l'IAM. L'**admin web**, lui, est le cockpit de
*l'humain* : lié à 127.0.0.1, il exécute déjà des mutations quand on clique
(unlock, grant, revoke). Un bouton IAM y est donc aussi légitime — le LLM ne
peut pas atteindre l'API admin (canal séparé + en-tête anti-CSRF + localhost).

## Proposition

1. Admin : panneau **« 🩺 Santé du setup »** (bouton d'en-tête) qui appelle
   `GET /api/setup` → `provision-gcp.sh status --json` (réutilise 0009) et
   affiche projet, publication, et l'accès IAM par compte (badge ok/manquant/
   non vérifié).
2. Bouton **« 🔧 Réparer l'accès »** (visible si au moins un compte manque) →
   `POST /api/sync-iam` → `provision-gcp.sh sync-iam --yes`. Idempotent.
3. Cohérence sécurité : `sync-iam` exige désormais **Touch ID** si `strongauth`
   est activé (comme unlock/grant) — terminal comme admin.

## Critères d'acceptation

- [x] Bouton 🩺 Setup dans l'admin ouvre un panneau montrant l'IAM par compte
      (mw → « sans rôle IAM », les autres « accès OK ») — vérifié navigateur.
- [x] Bouton « Réparer l'accès » présent quand un compte manque ; `POST
      /api/sync-iam` câblé (idempotent, `sync-iam --yes`).
- [x] `provision-gcp.sh sync-iam` passe par `require_strong_auth` (Touch ID si
      strongauth) — barrière physique, terminal et admin.
- [x] Le LLM ne peut pas déclencher la réparation (API admin hors de sa portée) ;
      la mutation reste un clic humain sur localhost.

## Notes

- Réutilise `status --json` (0009) — une seule source pour l'état IAM.
- Vérif : GET /api/setup renvoie mw=missing ; rendu du panneau + bouton OK.
  La réparation elle-même (clic → sync-iam) reste un geste humain, non exercé
  par l'agent (principe du projet).
- Corrige l'affirmation trop restrictive « réparation en terminal uniquement »
  des sessions précédentes.
