---
id: 0096
title: Socle de rendu sûr — fonction html`` échappant par défaut + filet de tests node
type: feature
priority: P0
product: google-mcp-multi-account
version:
epic: 0060
status: todo
ready: 2026-09-03
pr:
created: 2026-08-30
---

## En clair

Aujourd'hui l'admin colle son HTML à la main et doit penser à échapper chaque valeur
(`esc()`, `attr()`). Un oubli = faille d'injection. On introduit une petite fonction
``html`` `` (une *tagged template*) qui **échappe toute seule** ce qu'on insère, et on la
couvre par des tests exécutés sous `node`. C'est le socle technique sur lequel s'appuieront
les composants.

Référence : ADR-0010 (brique 2).

## Contexte / problème

Le rendu par concaténation impose un triple échappage (valeur dans un `onclick` dans un
attribut dans une template-string), d'où des rustines fragiles (`.replace(/'/g,"\\'")`).
Une seule feuille oubliée ouvre une injection. Le front n'a **aucun** test : `scripts/test.sh`
ne teste que l'API de `server.js`.

## Proposition

- Ajouter ``html`` `` (~15 lignes) : échappe chaque interpolation par défaut, avec un
  marqueur explicite pour un fragment déjà sûr.
- Poser `esc()`/`attr()` en dessous comme primitives.
- Filet de tests **sans jsdom** : exécuter les fonctions pures (`normDrive`, `capsHtml`,
  `fmtMins`, `mdToHtml`, ``html`` ``) sous `node` dans `scripts/test.sh`, dont un test
  d'injection `"><script>` qui doit être neutralisé.

## Critères d'acceptation

- [ ] ``html`` `` échappe par défaut ; un test d'injection prouve la neutralisation.
- [ ] Les fonctions pures ciblées tournent sous `node` dans `test.sh` (vert en CI).
- [ ] Comportement de rendu inchangé sur les écrans existants.

## Comment vérifier

`./scripts/test.sh` inclut les nouveaux tests node et passe au vert. Injecter une valeur
piégée dans une session/zone de test et vérifier qu'elle s'affiche littéralement, sans
exécution.
