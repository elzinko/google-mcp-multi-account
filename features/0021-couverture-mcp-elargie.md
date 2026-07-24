---
id: 0021
title: Élargir la couverture MCP — Calendar, Docs, Sheets, Tasks (et écritures)
type: feature
priority: P3
version:
epic: 0017
status: idea
ready:
pr:
created: 2026-07-24
---

## Contexte / Problème

Le README pitch 6 services. La réalité MCP : **9 tools dont 3 méta**. Gmail
(lecture + brouillon) et Drive (lecture + création) seulement. **Zéro tool MCP**
pour Calendar, Docs, Sheets, Tasks — accessibles uniquement via le shell `gwsa`,
donc **pas depuis Claude Desktop** (pourtant cible du script d'install 0013).

En face, les serveurs MCP Google concurrents exposent des dizaines à des centaines
d'outils sur 12+ services. L'équation d'adoption est défavorable : le setup le plus
coûteux du marché pour la couverture la plus étroite.

## Proposition

Exposer en tools MCP les services **déjà déclarés dans la policy** (donc sans
élargir le modèle de sécurité), sous le même cadre default-deny :

- **Lecture d'abord** : `calendar_list`/`agenda`, `tasks_list`, `sheets_read`,
  `docs_get` (miroir des skills `gws-*` existantes).
- **Écritures ensuite**, au cas par cas, en gardant le principe « pas d'action
  sortante sans geste humain » (brouillons, pas d'envoi ; pas de suppression déf.).

## Critères d'acceptation

- [ ] Au moins Calendar et Tasks en lecture, exposés comme tools MCP et testés
      (hermétique, comme Gmail/Drive).
- [ ] Chaque nouveau tool respecte la policy default-deny existante (déjà en place).
- [ ] Le README ne pitche que les services réellement exposés via MCP.

## Notes

Confort d'adoption, **hors chemin critique** de la généralisation (P3) : un
utilisateur peut déjà se servir de Gmail/Drive. La policy déclarant déjà ces
services, l'essentiel est mécanique. Voir épic [[0017]].
