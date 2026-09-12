---
id: "20260903155243879"
title: Admin mobile — cibles tactiles à 44 px (barre haute)
type: bug
priority: P3
product: google-mcp-multi-account
version:
epic: 0060
status: idea
ready:
pr:
created: 2026-09-03
---

## En clair

Sur mobile, les boutons-icônes de la barre haute de l'admin font **40 px**. Le plancher
tactile confortable est **44 px** (cible annoncée par la fiche mobile). On les agrandit pour
qu'ils soient faciles à toucher au pouce.

Reste de la fiche [`0104`](done/0104-app-shell-responsive-mobile.md), livrée par la refonte
Cockpit (#128) : l'app shell responsive est en place, seul ce plancher tactile n'est pas tenu.

## Contexte / problème

En dessous de 640 px, la barre haute mobile (`.ck-mtop`) affiche des `.ck-iconbtn` à 40 px
(`admin/index.html`). C'est sous le plancher de 44 px que la fiche 0104 elle-même annonçait.
Petites cibles = clics ratés au pouce.

## Proposition

- Porter `.ck-mtop .ck-iconbtn` (et toute cible tactile de la barre haute) à **≥ 44 px** en
  vue mobile, sans casser l'alignement de la barre.

## Critères d'acceptation

- [ ] En dessous de 640 px, les cibles tactiles de la barre haute mesurent ≥ 44 × 44 px.
- [ ] L'alignement et la hauteur de la barre haute restent corrects (clair et sombre).

## Comment vérifier

Émuler un écran 375 px, mesurer les boutons de la barre haute (inspecteur) : ≥ 44 px. Vérifier
que la barre ne déborde pas et reste alignée.
