---
id: 0029
title: Publier et mettre à jour en une commande (release semver + update façon installeur)
type: feature
priority: P1
version:
epic:
status: in-progress
ready: 2026-07-26
pr: "#28"
created: 2026-07-26
---

## Contexte / Problème

Publier une version demande aujourd'hui **cinq gestes manuels**, dans le bon
ordre, sans filet : merger, passer la fiche en shipped, choisir un numéro de
version à la main, `git tag -a` + `git push origin <tag>`, puis
`deploy-local.sh`, puis `install-claude-desktop.sh`.

Rien ne calcule le numéro suivant. Rien ne vérifie qu'on est sur `main`, à jour,
avec les tests au vert avant de taguer. Rien ne dit ce qu'apporte une version :
il faut lire le journal git. Et côté poste, mettre à jour n'est pas « une
commande » — c'est enchaîner deux scripts en sachant lequel d'abord.

C'est le chaînon qui manque pour que le projet se comporte comme un produit
installé : `npm version` d'un côté, `brew upgrade` de l'autre.

## Proposition

Deux commandes, chacune idempotente et refusant de travailler dans le flou.

**1 · `./scripts/release.sh [patch|minor|major]`** — publier

- Déduit le niveau des conventional commits depuis le dernier tag : un `feat`
  → minor, un `BREAKING CHANGE` (ou `type!:`) → major, sinon patch. L'argument
  force la main.
- Refuse : arbre sale, branche autre que `main`, retard sur `origin/main`, tag
  déjà existant, aucun commit depuis le dernier tag, tests rouges.
- Écrit `CHANGELOG.md` (section par version, commits groupés par type),
  commite, pose un tag annoté, pousse commit et tag.

**2 · `./scripts/update.sh`** — mettre à jour son poste

- Va chercher les tags publiés, prend le plus récent (`--to <version>` pour en
  viser un autre), et l'installe.
- Ne fait rien si c'est déjà la version courante (`--check` pour voir sans
  écrire).
- Déploie via `deploy-local.sh --tag`, bascule `current`, recycle le broker,
  et branche Claude Desktop **seulement si** l'entrée manque ou pointe ailleurs.
- Marche aussi depuis la copie installée : `deploy-local.sh` note le chemin du
  clone source dans `.source`, et `update.sh` s'y redirige quand il tourne hors
  dépôt git.

**3 · `deploy-local.sh --tag <version>`** — déployer une version **autre** que
celle de HEAD, sans toucher à l'arbre de travail. C'est ce qui permet à
`update.sh` d'installer une version pendant qu'on développe autre chose.

## Critères d'acceptation

- [x] `release.sh` sans argument déduit patch / minor / major des commits.
- [x] `release.sh` refuse : arbre sale, hors `main`, tag déjà posé, rien à
      publier, tests rouges — avec un message qui dit quoi faire.
- [x] `release.sh --print` n'écrit rien, ne pousse rien, mais annonce la
      version qui sortirait.
- [x] `CHANGELOG.md` gagne une section par version, commits groupés par type,
      la plus récente en haut.
- [x] `deploy-local.sh --tag v0.1.0` déploie ce tag même si HEAD est ailleurs,
      et refuse un tag inconnu.
- [x] `update.sh` installe la dernière version, puis relancé ne fait rien
      (« déjà à jour »).
- [x] `update.sh --check` n'écrit rien et affiche installé / disponible.
- [x] `update.sh --to <version>` installe une version précise.
- [x] Tests hermétiques : dépôt git jouet, aucun réseau, aucun compte réel.

## Notes

- Le tag reste la source de vérité de la version — `release.sh` ne fait que le
  calculer et le poser proprement.
- Publier une release GitHub (`gh release create`) est volontairement hors
  périmètre : le dépôt est privé et le CHANGELOG suffit. Tracé en fiche 0028.
- La détection du niveau suit le semver standard, y compris en 0.x : un
  breaking change fait passer la majeure.
