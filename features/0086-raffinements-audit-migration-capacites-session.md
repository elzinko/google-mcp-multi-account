---
id: 0086
title: Raffinements audit + migration de la couche capacités de session (suite revue PR #118)
type: bug
priority: P2
version:
epic: 0082
status: todo
ready:
pr:
created: 2026-08-18
---

## Contexte / Problème

Suite de la revue Codex de la PR #118 ([0080](0080-durcir-capacites-fines-session.md)). Le P0
(fail-open sur la dérivation de ressource) et les correctifs principaux (forme `--params={…}`,
`events import`, audit `copy`→destination, repli legacy des sous-sessions pré-snapshot) sont **livrés
dans 0080**. Restent **3 raffinements P2** — tous **fail-closed ou audit best-effort, aucun
fail-open** — différés ici pour arrêter une boucle de revue à rendement décroissant, la fiche 0080
remplissant ses critères (372/0, revue adverse GO).

## Proposition

1. **Aligner l'override `trashed` sur le chemin d'autorisation session** (`gateway/usage.py:~60`,
   `gateway/sessions.py` `_gate_drive_session`). L'audit reclasse `drive files update {trashed:true}`
   en `delete` (fiche 0037), mais sous policy Drive `open`/non-`zonesOnly` l'**autorisation** classe
   encore `update` : une cap `drive:update` autorise, l'audit journalise `delete` → triplet d'audit ≠
   capacité qui a réellement autorisé. Appliquer le même override côté **autorisation** avant de
   changer la catégorie d'audit (ou documenter l'écart assumé).
2. **Normaliser le service versionné avant l'inférence de ressource** (`gateway/usage.py:~61`,
   `infer_call`). `policy-check.py` normalise `calendar:v3` → `calendar` ; `infer_call` passe le brut
   `calendar:v3` dans le mapping opérande → ressource `""` dans l'audit pour les appels versionnés.
   Réutiliser la même normalisation (lowercase + retrait du suffixe de version) avant catégorisation
   et lookup opérande.
3. **Snapshoter les capacités *effectives* d'un parent legacy** (`gateway/sessions.py:~512`). Après
   upgrade, une session déléguée legacy voit bien les octrois de son ancêtre via le repli ; mais si
   elle crée un **enfant**, le snapshot copie sa liste locale **brute** (vide pour un fichier legacy)
   → le petit-enfant perd toutes les capacités que son parent peut pourtant exercer. Construire le
   snapshot depuis les capacités **résolues effectives** du parent (`active_capabilities()`), pas la
   seule liste persistée.

## Critères d'acceptation

- [ ] Sous policy Drive `open`, un `drive files update {trashed:true}` a la **même** catégorie côté
      autorisation et côté audit (`delete`) — testé.
- [ ] `calendar:v3 events list --params {calendarId:cal123}` journalise la ressource `cal123` (pas
      `""`) — testé.
- [ ] Un parent legacy (post-upgrade, capacités via repli) qui crée un enfant transmet ses capacités
      **effectives** au petit-enfant — testé.
- [ ] `./scripts/test.sh` vert.

## Notes

- **Limites assumées héritées de 0080** (mapping opérande mono-ressource) : `calendar events move`
  (2 agendas dans le même appel) et Gmail `messages modify`/`batchModify` (add + remove `labelIds`)
  sont **délibérément exclus** du mapping → `""` → **fail-closed** sous capacité scopée. À revisiter
  ici seulement si un usage réel scopé sur ces méthodes apparaît.
- Révélé par la revue Codex de la PR #118 (findings P2, répondus en fil et résolus). Parent :
  [0082](0082-droits-par-session.md) / [ADR-0007](../docs/adr/ADR-0007-droits-par-session.md).
  Fiche sœur de [0080](0080-durcir-capacites-fines-session.md) et [0085](0085-figer-unlock-zones-sous-session.md).
