---
id: 0026
title: Savoir quelle version répond — version annoncée par les tools, dérive détectée
type: feature
priority: P2
version:
epic:
status: idea
ready:
pr:
created: 2026-07-26
---

> **Frontière (non-doublon avec [[0042]]).** 0026 = surface **agent** : version
> annoncée via les tools (`setup_status`) + détection de dérive config ↔
> `current`. La visibilité **humaine** (Connecteurs / admin), le parcours de
> mise à jour post-merge et la cohabitation stable/dogfood vivent dans [[0042]].

## Contexte / Problème

Rien ne dit, depuis une conversation, quelle version du MCP répond. Il faut
ouvrir un terminal et rejouer le handshake `initialize` à la main.

Pire : rien ne détecte la dérive entre ce qui est **déployé** et ce qui est
**branché**. Le cas s'est produit — le couloir stable existait (fiche 0023)
mais Claude Desktop lançait toujours le clone de travail, découvert seulement
en fouillant la config à la main le 2026-07-26.

## Proposition

- `setup_status` annonce sa propre version et son couloir (chemin du binaire,
  port du broker) : l'agent sait à qui il parle, sans terminal.
- Une commande de contrôle (`deploy-local.sh --check` ou `gwsa doctor`) qui
  compare l'entrée réellement branchée dans la config du client avec
  `~/.local/share/google-mcp/current`, et signale l'écart.

## Critères d'acceptation

- [ ] À groomer.

## Notes

Découvert en même temps que la fiche 0025 (couloirs étanches).

**Suite 2026-07-28** : la surface Claude Desktop → Connecteurs n'affiche
toujours pas la version (seulement le nom `google-multi-account` + permissions
outils). Voir fiche [[0042]] pour la visibilité « humaine » + parcours de mise
à jour post-merge ; cette fiche 0026 reste centrée sur l'annonce **via tools**
et la dérive config ↔ `current`.
