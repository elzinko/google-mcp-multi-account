---
id: "20260905175129735"
title: Durcir le cluster updater — findings Codex post-merge (#134/#135/#136)
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

Le cluster updater (0081/0091/0092) est livré, mais Codex a relevé — **après merge** (les PRs #134/#135/#136
ont été fusionnées sur revue-adverse-GO + CI verte, avant que Codex réponde) — plusieurs trous. Deux
familles : (A) le **rollback à travers le renommage `gma→mag`** (#134/#135), la raison d'être du cluster ;
(B) la **dépréciation `gwsa` + le guide de refresh** (#136, fiche 0092). Aucun ne casse le cas courant.
Les rollback sont rares et récupérables par réinstall ; côté 0092, deux vrais défauts (condition du
message inversée, test de non-régression qui ne teste pas ce qu'il prétend) + deux durcissements.
**Non groomé** (ready vide) : à cadrer avant de tirer.

## Groupe A — rollback (PR #134/#135)

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

## Groupe B — dépréciation gwsa + refresh (PR #136, fiche 0092)

- **[P2] `scripts/update.sh:248` — condition du guide de refresh inversée.** Le bloc « ton shell ne
  voit pas encore `mag`, fais `hash -r` » est gardé par `command -v mag`… mais exécuté dans le PROCESSUS
  de `update.sh`, pas dans le shell interactif appelant. Or `retarget_cli_links` vient de poser/reciblé
  `mag` juste avant → `command -v mag` réussit **dans ce process** → le guide est **masqué justement
  quand le shell appelant a le cache obsolète** (le cas visé). **Fix** : ne pas déduire l'état du shell
  appelant depuis le process de l'updater — afficher le guide inconditionnellement après un update qui a
  (re)posé `mag`, ou détecter le cache autrement.

- **[P2] `bin/mag:116` — identifiant de session réutilisable dans la clé du marqueur.** En interactif la
  clé = le seul chemin TTY (`/dev/ttys001`…), réutilisé après fermeture du terminal, alors que le marqueur
  n'est jamais nettoyé → un terminal ultérieur qui hérite du même chemin est traité « déjà averti » →
  l'avertissement de dépréciation peut se taire pour de bon. **Fix** : composer la clé avec un identifiant
  non réutilisable (ex. horodatage de démarrage du shell) ou expirer le marqueur.

- **[P2] `bin/mag:126` — sécurité : suivre un symlink dans `/tmp` partagé.** Si `TMPDIR` est vide, le
  marqueur a un nom prévisible dans `/tmp`. Un utilisateur local peut le pré-créer en symlink pendouillant
  vers un chemin inscriptible par la victime ; `[[ -e "$marker" ]]` ne voit pas un symlink cassé comme
  existant, et le `touch` le suit → la victime crée un fichier vide arbitraire. **Fix** : `mkdir` d'un
  sous-dossier propre au marqueur, ou `-h`/`O_NOFOLLOW`, ou refuser un `/tmp` partagé sans TMPDIR.

- **[P2] `scripts/test.sh:5706` — le test de non-régression ne teste pas ce qu'il prétend.** En CI
  hors-TTY, chaque `$(...)` tourne dans un sous-shell différent → `$PPID` différent → les deux appels sont
  « à froid » (avertissement présent aux deux) : le test compare donc deux sorties froides, jamais
  froid-vs-chaud. Une régression qui émettrait l'avertissement sur **stdout** aux deux appels passerait
  inaperçue. **Fix** : forcer une clé de session commune via l'override `GWSA_DEPRECATION_SESSION_KEY`
  (déjà ajouté au fix #137) pour un appel « chaud » déterministe, et comparer froid-vs-chaud.

## Comment vérifier

Test hermétique reproduisant — **Groupe A** : (1) `mag update --to <pré-helper>` **depuis la copie
installée** → liens reciblés, commandes invocables ; (2) 1ʳᵉ install de la feature via ancien updater →
`previous` amorcé, `revert` disponible ; (3) `previous` absent de `--list` et refusé comme cible
`--rollback` ; (4) 2ᵉ revert via le lien PATH reciblé. **Groupe B** : (5) après un update qui pose `mag`,
le guide de refresh s'affiche bien (condition non inversée) ; (6) le test de non-régression compare
vraiment chaud-vs-froid (clé de session forcée).

## Notes

- Suite du cluster [[0081]] / [[0091]] / [[0092]]. Origine : findings Codex sur PRs #134, #135 **et #136**,
  restés non traités car les PRs ont été mergées avant la réponse Codex (revue adverse ezk-reviewer +
  CI verte servaient de gate ; #136 a même posté après le check de clôture → raté sur le coup). Leçon
  process : attendre Codex avant merge, ou traiter ses findings en suivi de façon systématique.
- Hors périmètre de cette fiche : #133 (régression d'affichage des dialogues) — **déjà corrigée** dans
  la PR #137 (commit 6e4fc79). Seuls ses fils Codex restaient à acquitter (fait le 2026-09-06).
- Le test-validity du Groupe B (#136, test.sh:5706) est **le même défaut** que le test « once-per-session »
  déjà durci au fix #137 via `GWSA_DEPRECATION_SESSION_KEY` : réutiliser cet override pour rendre la
  comparaison froid-vs-chaud déterministe.
