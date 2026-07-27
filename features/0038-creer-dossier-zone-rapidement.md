---
id: 0038
title: Créer un dossier-zone rapidement, geste humain (sans passer par le LLM)
type: feature
priority: P2
version:
epic:
status: idea
ready:
pr:
created: 2026-07-27
---

## Contexte / Problème

Accorder une zone suppose que le dossier existe **déjà**, créé par l'humain
(c'est voulu : la frontière appartient à l'humain, cf. fiche 0037). Mais le
créer aujourd'hui oblige à quitter l'admin, ouvrir Drive web, faire « Nouveau
dossier », revenir. Friction inutile pour un geste fréquent.

Constaté au test du 2026-07-27 : les dossiers `ZZ-TESTS` avaient dû être créés
à la main au préalable, hors de tout outil du projet.

## Proposition

Depuis la fenêtre d'ajout de zone de l'admin, deux variantes possibles :

- **Lien** : un bouton « 📁 Créer un dossier dans Drive… » qui ouvre la page
  Drive de création (l'humain nomme, crée), puis revient sélectionner le
  dossier comme zone.
- **Création directe** : l'admin crée le dossier lui-même (via `bin/gwsa` /
  `gws`, geste **humain** initié par le bouton, jamais par le LLM), puis le
  propose aussitôt comme zone.

Dans les deux cas, le principe tient : **c'est l'humain qui crée la frontière**,
le LLM ne fait que travailler dedans. On enlève la friction, pas la garde.

## Critères d'acceptation

- [ ] À groomer.

## Notes

- La création reste un geste humain (bouton admin), jamais une capacité LLM —
  cohérent avec le modèle de la fiche 0037 (l'humain possède la frontière).
- Ne pas confondre avec `drive_create` côté MCP (le LLM crée *dans* une zone
  déjà accordée) : ici c'est l'humain qui crée *la zone elle-même*.
