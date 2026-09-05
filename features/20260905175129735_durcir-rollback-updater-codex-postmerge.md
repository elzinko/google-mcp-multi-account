---
id: "20260905175129735"
title: Durcir le rollback updater — findings Codex post-merge (#134/#135)
type: bug
priority: P2
product: google-mcp-multi-account
version:
epic:
status: todo
ready:
pr:
created: 2026-09-05
---

## En clair

Le cluster updater (0081/0091/0092) est livré, mais Codex a relevé — **après merge** (les PRs #134/#135
ont été fusionnées sur revue-adverse-GO + CI, avant que Codex réponde) — trois trous qui touchent le
**rollback à travers le renommage `gma→mag`**, la raison d'être du cluster. Aucun ne casse le cas
courant ; tous concernent des chemins de rollback rares, récupérables par réinstall. À traiter dans un
lot « durcissement rollback ». **Non groomé** (ready vide) : à cadrer avant de tirer.

## Findings à traiter

- **[P1] `scripts/update.sh` — capturer/​sourcer le helper AVANT de rebasculer `current`** (Codex PR #134).
  Quand `mag update --to <release pré-helper>` est lancé depuis la copie installée (`$0` sous
  `$DEPLOY_ROOT/current`), le déploiement rebascule `current` sur la release legacy **avant** que
  `update.sh` ne source `scripts/lib/cli-link.sh` ; le helper est alors cherché DANS la release legacy
  (qui ne l'a pas) → le garde `-f` échoue → les liens ne sont pas reciblés → commandes cassées. C'est
  le scénario exact que 0081 devait réparer, mais seule la voie `deploy-local.sh --rollback` (directe,
  depuis un clone) fonctionne ; la voie `mag update --to` depuis l'installé reste cassée. **Fix** :
  résoudre/sourcer le helper avant la bascule ; même souci pour `deploy-local.sh --rollback` invoqué
  via `current`.

- **[P1] `bin/mag` — amorcer `previous` à la 1ʳᵉ mise à jour qui introduit `mag revert`** (Codex PR #135).
  Pour une install sans clone, l'update qui installe la feature est exécuté par l'ANCIEN `update.sh` →
  ancien `deploy-local.sh`, qui ne pose pas `previous`. Donc juste après l'upgrade vers la release qui
  contient `mag revert`, `revert` tombe toujours sur « aucune version précédente », alors que l'ancienne
  version est encore déployée. **Fix** : repli rétro-compatible (dériver/enregistrer l'ancienne cible
  `current` si `previous` manque).

- **[P2] `scripts/deploy-local.sh` — exclure `previous` de l'énumération des versions** (Codex PR #135).
  Le symlink-dossier `previous` est suivi par la boucle `--list` (`$DEPLOY_ROOT/*/`, qui n'exclut que
  `current`) → l'utilisateur voit `previous` comme une version. Et `--rollback previous` est accepté
  par le test `-d`, mais `point_current_at` écrase `previous` avant d'y pointer `current` → perte de la
  vraie cible. **Fix** : réserver/ignorer `previous`.

- **[P2] `scripts/test.sh` — tester le 2ᵉ revert via le lien PATH reciblé** (Codex PR #135).
  Le test enchaîne le 2ᵉ revert via `$GW` (binaire du clone) et non `$LINK` (reciblé sur l'ancienne
  release). Comme la release précédente est antérieure au commit, son `mag` n'a pas le verbe `revert` :
  un vrai 2ᵉ `mag revert` échouerait. Le test devrait passer par `$LINK` — ce qui **révèle** une
  limite réelle (revert indisponible après downgrade vers une release pré-revert). À décider : accepter
  la limite (documentée) ou garder le lien `mag` courant même après downgrade.

## Comment vérifier

Test hermétique reproduisant : (1) `mag update --to <pré-helper>` **depuis la copie installée** →
liens reciblés, commandes invocables ; (2) 1ʳᵉ install de la feature via ancien updater → `previous`
amorcé, `revert` disponible ; (3) `previous` absent de `--list` et refusé comme cible `--rollback` ;
(4) 2ᵉ revert via le lien PATH reciblé.

## Notes

- Suite du cluster [[0081]] / [[0091]] / [[0092]]. Origine : findings Codex sur PRs #134 et #135,
  restés non traités car les PRs ont été mergées avant la réponse Codex (revue adverse ezk-reviewer +
  CI verte servaient de gate). Leçon process : attendre Codex avant merge, ou traiter ses findings en suivi.
