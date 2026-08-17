---
id: 0081
title: Durcir la couche d'approbation passkey distante (suite revue Codex #113)
type: feature
priority: P2
version:
epic: 0077
status: todo
ready:
pr:
created: 2026-08-17
---

## Contexte / Problème

Le POC d'approbation par passkey distante ([0078](done/0078-approbation-passkey-archi-actuelle.md),
PR #113, [ADR-0009](../docs/adr/ADR-0009-approbation-passkey-distante.md)) livre « le téléphone
signe, le Mac vérifie et exécute — sinon rien ». La revue Codex de #113 a laissé **deux
durcissements non bloquants** (findings P2, répondus en fil), différés ici pour ne pas retarder le
merge du cœur — le fail-closed, l'anti-rejeu (`consume_nonce`) et la liaison `session_id` étant,
eux, déjà en place dans #113.

Un **troisième** différé — le vrai canal *out-of-process* (push / relais aveugle chiffré E2E, app
mobile, holder natif) — **ne relève pas de cette fiche** : c'est un incrément de l'épic
[0077](0077-acces-mobile-souverain.md) (« relais aveugle », déjà prévu), pas un durcissement de
l'existant.

## Proposition

1. **Sérialiser la vérification anti-clonage `sign_count` (TOCTOU)** — dans
   `gateway/remote_approval.py`, `verify_assertion` lit-et-compare `sign_count <= enrollment.sign_count`
   (rejet, l. 334) puis, plus loin, persiste `enrollment.sign_count = sign_count` + `_save_enrollment`
   (l. 344-345) **sans atomicité**. Deux `verify_assertion` concurrents sur la même assertion peuvent
   tous deux franchir le check avant qu'aucun n'ait persisté le nouveau compteur : une passkey
   **clonée** rejouée passerait l'anti-clonage. Sérialiser lecture-check-écriture derrière **un verrou
   de concurrence** (même classe de correctif que le TOCTOU déjà connu sur `consume_nonce` / broker).
   Le `sign_count` reste **authentifié par la signature** (non forgeable) — d'où la sévérité **P2**.

2. **Renforcer le test CA3 « NO_MUTATION »** — dans `scripts/test.sh` (bloc CA3, ~l. 4280), le test
   prouve que les trois chemins de refus (refus explicite, nonce expiré, signature invalide) ne
   renvoient aucun payload exécutable et laissent une session témoin verrouillée. Mais `NO_MUTATION:ok`
   est **quasi-tautologique** : rien, dans le POC, ne déverrouille jamais cette session par ce chemin —
   l'assertion « pas de mutation » passerait même si l'exécution était cassée. Lui donner du mordant =
   un **contrôle positif** jumeau : une approbation **valide** qui **fait** basculer
   `is_session_unlocked`, prouvant que le même observable *aurait* muté sur le chemin succès. À câbler
   quand **`gate → exécution réelle`** sera branché (l'appelant exécute `session_unlock` avec le payload
   signé retourné par `run_remote_approval_gate`).

## Critères d'acceptation

- [ ] `verify_assertion` sérialise check-puis-persistance de `sign_count` : deux vérifications
      **concurrentes** de la même assertion ⇒ **une seule** réussit, l'autre est refusée
      (`sign_count` non strictement croissant) — testé sous concurrence.
- [ ] Le test CA3 dispose d'un **contrôle positif** : une approbation valide **déverrouille** la
      session témoin (`is_session_unlocked` → vrai), de sorte que l'assertion `NO_MUTATION` des chemins
      de refus devient discriminante — testé.
- [ ] `./scripts/test.sh` vert.

## Notes

- Suite de la revue Codex de la PR #113 (findings P2 répondus en fil). Parent :
  [0078](done/0078-approbation-passkey-archi-actuelle.md) /
  [ADR-0009](../docs/adr/ADR-0009-approbation-passkey-distante.md) — dont les *Conséquences*
  soulignent déjà que `sign_count` doit être strictement croissant **et persisté à chaque
  vérification**, sinon une passkey clonée passerait (c'est le point durci ici).
- **Fiche sœur** de [0080](0080-durcir-capacites-fines-session.md) (« durcir … suite revue Codex #110 »
  sur la couche *session*) : même patron « durcissements différés d'une revue Codex ». Le TOCTOU (1)
  est de la **même classe** que le TOCTOU `consume_nonce` déjà répertorié — à traiter d'un même geste
  de verrouillage si les deux sont tirés ensemble.
- Le critère n°2 **dépend** du branchement `gate → exécution réelle` : aujourd'hui le POC stubbe le
  transport (`GWSA_REMOTE_SIGNER` + `--response`, cf. `scripts/remote-approval-cli.py` / `bin/gwsa`).
  À livrer **avec** ou **après** ce branchement.
- Le 3ᵉ différé (vrai canal push / relais aveugle E2E + app mobile + holder natif) **reste dans l'épic
  [0077](0077-acces-mobile-souverain.md)** (incrément « relais aveugle » déjà prévu) — hors de cette
  fiche.
