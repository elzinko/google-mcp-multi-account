---
id: 0081
title: Durcir updater/deploy — rollback à travers le renommage mag & liens PATH cassés
type: bug
priority: P2
version:
epic:
status: todo
ready: 2026-09-04
pr:
created: 2026-08-17
---

## En clair

Deux bugs rares mais gênants du **retour en arrière** de l'updater, à travers le renommage
`gma → mag`. **Un** : si on revient à une version d'**avant** le renommage, les liens PATH
pointent vers un `mag` qui n'existe pas encore et l'updater n'applique pas son repli → commandes
cassées. **Deux** : `deploy-local.sh --rollback` change la version mais **ne recible pas** les
liens PATH. On répare les deux (récupérable sans réinstall). C'est le **socle** du cluster
updater (les fiches 0091 et 0092 s'appuient sur son helper de re-ciblage partagé).

## Contexte / Problème

Le renommage `gma → mag` (PR #114) introduit un **point de bascule** dans l'historique
des versions : les releases d'**avant** le renommage n'ont que `bin/gwsa`/`bin/gma`, pas
`bin/mag`. La revue Codex de #114 a durci l'essentiel (repli sur `bin/gwsa`/`bin/gma`
dans `link_cli` et `stop_broker`, réparation des alias, etc. — rounds 1→4), mais deux
edge-cases de **rollback à travers le renommage** restent ouverts (round 5). Ils sont
**rares** (rollback explicite vers une version antérieure au renommage) et **récupérables**
par une simple réinstall (`curl … | sh`), d'où le report hors de la PR de renommage.

## Findings à traiter (Codex #114, round 5)

- **`scripts/update.sh` — localiser un lien cassé sans `command -v`** (P1 Codex).
  `command -v mag|gma|gwsa` **ignore un symlink dont la cible n'existe plus**. Lors de
  `mag update --to <tag pré-renommage>`, `current` bascule d'abord ; les 3 liens installés
  pointent alors vers `current/bin/mag` (désormais absent), aucun `command -v` ne renvoie
  de chemin, `link_cli` sort avant d'appliquer le repli `bin/gwsa`. → **Dériver le chemin
  du lien indépendamment de son exécutabilité** (chemins connus `~/.local/bin`, `brew --prefix`,
  ou `GWSA_CLI_LINK`), ou **capturer le chemin AVANT** le switch de `current`.

- **`scripts/deploy-local.sh --rollback <version pré-renommage>` — re-cibler les liens** (P1 Codex).
  Le rollback direct via `deploy-local.sh` bascule `current` mais **ne réécrit jamais** les
  liens PATH `mag`/`gma`/`gwsa` → toutes les commandes sont cassées après le rollback
  « réussi ». `stop_broker` sait déjà se replier sur le binaire legacy ; il faut **appliquer
  la même cible aux liens PATH** dans le chemin rollback (extraire la logique de `link_cli`
  en helper partagé update ↔ deploy-local).

## Critères d'acceptation (BDD)

- **Given** une install sur `mag` **When** `mag update --to <tag pré-renommage>` **Then**
  `mag`/`gma`/`gwsa` pointent vers `current/bin/gwsa` et restent invocables (updater
  récupérable sans réinstall).
- **Given** une install **When** `deploy-local.sh --rollback <pré-renommage>` **Then** les
  3 liens PATH sont re-ciblés vers le binaire legacy et le broker est recyclé.
- Test hermétique simulant un lien cassé (cible absente) + un rollback pré-renommage.

## Comment vérifier

Test hermétique : simuler un lien cassé (cible absente) puis `mag update --to <tag pré-renommage>`
→ `mag`/`gma`/`gwsa` pointent vers `current/bin/gwsa` et restent invocables. Puis
`deploy-local.sh --rollback <pré-renommage>` → les 3 liens PATH sont reciblés vers le binaire
legacy et le broker recyclé. Aucune réinstall nécessaire.

## Notes

- Corrections déjà livrées dans #114 (à ne pas refaire) : repli `bin/gwsa`/`bin/gma` dans
  `link_cli`/`stop_broker`, réparation des alias même si `mag` déjà correct, création de
  `mag` dans le cas « déjà à jour ».
- Codex a coté ces deux points **P1** ; classés **P2** ici car le scénario est rare
  (rollback explicite à travers le renommage) et **récupérable par réinstall**.
