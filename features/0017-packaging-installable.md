---
id: 0017
title: Packaging installable — sortir du git clone + symlink codé en dur
type: feature
priority: P2
version:
epic: 0014
status: idea
ready:
pr:
created: 2026-07-24
---

## Contexte / Problème

L'installation actuelle : `git clone`, puis symlink **`/opt/homebrew/bin/gwsa`**
codé en dur, puis édition manuelle de `claude_desktop_config.json` (industrialisée
par la fiche 0013). Aucune **release**, aucun **artefact installable**. Un
utilisateur doit cloner le dépôt et connaître les chemins.

L'écosystème MCP a un vecteur de distribution moderne pour exactement ce cas : les
**Desktop Extensions `.mcpb`** (installation en un clic, répertoire, config gérée)
— qui rendent le mécanisme de la fiche 0013 en partie legacy.

## Proposition

- Packager le serveur MCP en **Desktop Extension `.mcpb`** (manifest, entrée MCP,
  variables), installable sans cloner ni éditer de chemin.
- Publier des **releases** (tag + artefact téléchargeable).
- Retirer / rendre optionnel le symlink `/opt/homebrew` (dépend de 0015).

## Critères d'acceptation

- [ ] Un utilisateur installe le serveur **sans cloner le repo** ni éditer un chemin.
- [ ] Un `.mcpb` (ou installeur équivalent) branche Claude Desktop en un geste.
- [ ] Une release téléchargeable existe, versionnée.

## Notes

Dépend de [[0015]] (chemins portables) pour un `.mcpb` non-macOS. Coordonner avec
la fiche 0013 (déjà livrée) pour ne pas dupliquer le branchement. Voir épic [[0014]].
