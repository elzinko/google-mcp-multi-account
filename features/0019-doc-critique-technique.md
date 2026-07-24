---
id: 0019
title: Doc de critique technique lisible (forces / limites / risques) référencée au README
type: feature
priority: P2
version:
epic:
status: todo
ready: 2026-07-24
pr:
created: 2026-07-24
---

## Contexte / Problème

Le projet n'a pas de **regard critique consolidé et lisible** pour un développeur
qui l'évalue ou veut y contribuer. L'information existe mais est **éclatée** :
`docs/threat-model.md` (sécurité seule), la section « Limites connues » du README
(3 puces), et les fiches backlog. Aucun **point d'entrée unique** qui explique
honnêtement, en clair, ce que vaut le projet, contre quoi il protège vraiment, de
quoi il dépend, et ce qui pourrait le rendre obsolète.

Une critique de session (2026-07-24) a produit la matière : barrière de sécurité
en grande partie **conventionnelle** pour un agent avec shell (contournement
documenté), **dépendance** à un CLI tiers pré-v1.0 (`gws`), **macOS-only** non
annoncé, **couverture MCP étroite** face à la concurrence, **friction OAuth**
Google, et risque d'**obsolescence** si le multi-comptes officiel arrive.

## Proposition

Écrire `docs/critique.md` : une analyse **claire et simple**, orientée
développeur (phrases courtes, une idée par phrase), qui assume les forces ET les
limites, renvoie vers les fiches/docs concernés, et cite des **références
externes** vérifiées. La référencer depuis le README (section dédiée).

## Critères d'acceptation

- [ ] `docs/critique.md` existe : structure lisible (verdict, forces, limites par
      thème, position vs concurrence, ce qui pourrait rendre le projet obsolète).
- [ ] Ton **factuel et honnête** — ni auto-flagellation ni argumentaire de vente.
- [ ] Chaque limite **renvoie** à la fiche/doc concerné (0003 vault, 0014/0015
      généralisation, 0018 couverture MCP, `docs/threat-model.md`).
- [ ] **Références externes vérifiées** (gws + issues, spec MCP, scopes Google /
      CASA, Desktop Extensions `.mcpb`, un serveur MCP concurrent).
- [ ] Référencé depuis le **README** (lien visible).
- [ ] `./scripts/test.sh` reste vert (aucun code touché) ; liens internes valides.

## Notes

Source : critique de session du 2026-07-24 (4 lentilles : marché, sécurité,
ingénierie, stratégie). En **français** pour l'instant, cohérent avec le repo — la
version anglaise relèvera de [[0016]]. Ce doc complète `threat-model.md` (focalisé
sécurité) par une vue produit / ingénierie / stratégie.
