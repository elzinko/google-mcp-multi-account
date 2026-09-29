---
id: "20260929172213000"
title: Détecter la dérive config client ↔ déploiement — deploy-local.sh --check
type: feature
priority: P2
product: google-multi-account
version:
epic:
status: ready
ready: 2026-09-29
pr:
created: 2026-09-29
---

## En clair

`setup_status` annonce déjà la version et le couloir (fiche [[0026]], PR #151). Reste l'autre
moitié : **détecter la dérive**. Aujourd'hui rien ne dit si le client (Claude Desktop/Code)
lance une **autre** version que celle déployée dans `~/.local/share/google-mcp/current`. Cette
fiche ajoute un contrôle qui compare les deux et signale l'écart.

Carvé de [[0026]] (POC version livré #151 ; dérive reportée — c'était un morceau à part).

## Contexte / problème

Le cas s'est déjà produit : le couloir stable existait, mais Claude Desktop lançait encore le
clone de travail — découvert seulement en fouillant la config à la main. Il manque un contrôle
qui compare l'entrée **réellement branchée** dans la config du client avec le lien
`~/.local/share/google-mcp/current`.

## Proposition

- `scripts/deploy-local.sh --check` : lit l'entrée branchée dans la config du/des client(s)
  MCP (chemin du binaire lancé) et la compare à `current`. Signale un écart (sortie non-zéro +
  message clair), ou confirme l'alignement.
- Lecture seule : aucune modification de config. Le correctif reste un geste humain proposé.

## Critères d'acceptation

- [ ] `deploy-local.sh --check` compare le binaire branché (config client) à `current` et
      signale la dérive (aligné → OK ; différent → écart nommé).
- [ ] Lecture seule ; ne modifie aucune config client.
- [ ] Test hermétique : config bidon pointant ailleurs que `current` → écart détecté ; config
      alignée → pas d'écart.
- [ ] `./scripts/test.sh` vert.

## Comment vérifier

Brancher une config client bidon vers un faux chemin, lancer `deploy-local.sh --check` → il
signale l'écart. Aligner sur `current` → il confirme.

## Notes

- Suite directe de [[0026]] (version annoncée par les tools, POC livré PR #151).
- La lecture de la config réelle du client (Claude Desktop, multi-plateforme) est le vrai
  morceau : la traiter dans son propre cycle plutôt que plaqué en fin de sprint 0026.
