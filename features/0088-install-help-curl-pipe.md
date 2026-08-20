---
id: 0088
title: Aide de install.sh vide sous « curl | bash » (--help relit $0)
type: bug
priority: P2
version:
epic:
status: in-progress
ready: 2026-08-20
pr:
created: 2026-08-20
---

## Contexte / Problème

Repéré en revue de la fiche 0087 (ezk-reviewer, P2 **hors-diff**). Ce n'est pas
une régression de 0087 : la ligne d'aide existait déjà et n'a pas changé.

La branche `-h`/`--help` de `install.sh` imprime l'aide en relisant l'en-tête
commenté du script :

```sh
-h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
```

Or le chemin d'installation **documenté** est `curl -fsSL …/install.sh | bash`.
Avec `curl … | bash -s -- --help`, bash lit le script sur **stdin** : `$0` vaut
« bash » (pas un chemin de fichier). `sed` lit alors le mauvais fichier — ou
rien — et l'**aide est vide** (mesuré : 0 octet).

Les autres scripts (`scripts/*.sh`, `bin/mag`) utilisent le même motif
`sed`/`awk … "$0"`, mais sont toujours invoqués **en tant que fichier** installé
sur le PATH : `$0` y est un chemin valide, ils ne sont pas concernés.
`install.sh` est le **seul** lancé par `curl | bash`.

## Proposition

Faire porter l'aide par le script lui-même via une **heredoc** (`usage()`), au
lieu de relire `$0` — robuste quel que soit le mode de lancement (fichier ou
stdin). `usage()` devient l'unique source de vérité de l'aide ; l'en-tête du
fichier est allégé et documente ce choix.

## Critères d'acceptation

- [x] `bash install.sh --help` imprime une aide non vide (lancement fichier).
- [x] `printf '%s' "$(cat install.sh)" | bash -s -- --help` imprime une aide non
      vide (lancement « curl | bash » simulé — le cas cassé).
- [x] `install.sh` passe `bash -n` avec le bash du système (macOS 3.2).
- [x] `--wire` et le rejet d'un argument inconnu (0087) restent intacts.
- [x] `scripts/test.sh` reste vert.

## Notes

Test hermétique ajouté dans `scripts/test.sh` : `install.sh` entre dans la boucle
de contrôle de syntaxe (bash 3.2) et une section vérifie l'aide par les **deux**
voies (fichier + stdin). Garde-fou validé : sur le code d'avant le fix, la voie
stdin rend 0 octet ; après, 1107 octets.
