---
id: 0007
title: Provisioning GCP idempotent/déclaratif — durcir provision-gcp.sh ou passer à Terraform
type: feature
priority: P2
version:
epic:
status: shipped
ready:
pr: "#10"
created: 2026-07-22
---

## Contexte / Problème

`scripts/provision-gcp.sh` est un script bash impératif : il vérifie l'état
avant certaines actions mais n'est pas garanti idempotent ni déclaratif, et
la reprise du projet par un tiers repose sur la lecture du script. Question de
revue (2026-07-22) : ne vaudrait-il pas un outil à **commandes reproductibles
et idempotentes** (Terraform ou équivalent) pour la partie GCP ?

## Proposition

Trancher entre deux voies, l'infra GCP se découpant en deux zones :

**Zone automatisable (déclarative possible)** — projet, activation des 8 APIs,
bindings IAM `serviceUsageConsumer` par compte (cf. 0005) :
- **Option A — bash durci** : rendre `provision-gcp.sh` strictement
  idempotent (chaque mutation précédée d'un check `describe`/`get-iam-policy`,
  ré-exécutable sans effet de bord), `status` diff l'état voulu ↔ réel.
  Zéro dépendance, colle à l'ADN « 100 % local, outillage minimal ».
- **Option B — Terraform (provider google)** : `google_project`,
  `google_project_service`, `google_project_iam_member`. Idempotent et
  diffable par nature (`terraform plan`), state local (`local` backend).
  Coût : dépendance binaire + gestion du tfstate.

**Zone NON automatisable (bloquant, quelle que soit l'option)** — Google
interdit de créer par API/IaC : le **client OAuth type Desktop app** et la
**publication de l'écran de consentement**. Ces deux gestes restent manuels
(console), donc aucune des deux voies ne rend le flux *entièrement*
déclaratif. Terraform ne couvrirait que le sous-ensemble projet/API/IAM.

**Recommandation (à débattre)** : commencer par l'option A (durcir le bash,
gain immédiat, pas de dépendance), et n'introduire Terraform que si le besoin
de diff/reproductibilité sur les bindings IAM multi-comptes le justifie —
auquel cas Terraform ne possède QUE la zone automatisable, le reste restant
documenté (docs/setup-oauth.md). Ne pas viser un « tout Terraform » illusoire
à cause des deux gestes manuels.

## Critères d'acceptation

- [x] Voie choisie et justifiée : **bash durci** (décision PO 2026-07-22 —
      pas de dépendance ni tfstate ; Terraform ne couvrirait de toute façon
      pas les 2 gestes OAuth manuels). Pas d'ADR requis (pas de Terraform).
- [x] Idempotence prouvée par double exécution sur la zone automatisable :
      `status` (lecture seule) et `sync-iam` (comptes en place → « déjà OK »
      ×N, zéro mutation ; non-tty sans `--yes` = no-op). La double exécution
      du flow interactif complet (étapes console) se re-valide au prochain
      onboarding réel — étapes 3–6 détectaient déjà l'existant, l'étape 7
      (publication) est désormais mémorisée (`PUBLISHED` dans provision.env).
- [x] Frontière automatisable / manuel explicite : en-tête du script
      (Automatisé / Guidé) + docs/setup-oauth.md.
- [x] Bindings IAM de 0005 intégrés : `sync-iam` réutilise la même détection
      (`iam_profile_states`) que `status` — une seule source pour « qui a le
      rôle ».

## Notes

- Étroitement lié à 0005 (les bindings IAM sont le principal candidat au
  déclaratif). Fusion possible si on part sur bash durci.
- Contrainte produit : rester local-first, pas de state cloud.
