---
id: 0023
title: Versionner et déployer le MCP en local, découplé du code source de travail
type: feature
priority: P0
version:
epic:
status: idea
ready:
pr:
created: 2026-07-25
---

## Contexte / Problème

Le serveur MCP en service **exécute le working tree**, en direct. Trois faits
constatés le 2026-07-25 :

- `bin/google-mcp` résout `REPO` depuis sa propre position, puis `cd "$REPO"` et
  `PYTHONPATH="$REPO"` — le code chargé est celui du clone, dans l'état où il se
  trouve à l'instant de l'invocation.
- La fiche [[0013]] (livrée) fait pointer Claude Desktop sur le **chemin absolu de
  `bin/google-mcp` du clone courant** — c'est le mécanisme, et il est volontaire.
- **Aucun tag git, aucune release**, et `SERVER_VERSION = "0.1.0"` en dur dans
  [`gateway/mcp_server.py:16`](../gateway/mcp_server.py) depuis l'origine : le
  serveur annonce une version qui ne veut rien dire.

Conséquence : impossible de développer sans exposer l'outil en service. Un
`git checkout`, un fichier à moitié édité, un import cassé — et Claude Desktop /
Claude Code perd son serveur MCP, ou pire **exécute du code non validé qui a
accès à de vraies données Google** (Gmail, Drive des comptes connectés). Le
rayon d'action du bug de développement n'est pas le test : c'est la production.

Il n'existe aujourd'hui aucun moyen de dire « la version que j'utilise » par
opposition à « la version sur laquelle je travaille ».

## Pistes à arbitrer au grooming

Aucune direction n'est arrêtée — la fiche est capturée pour ne pas perdre le
besoin, pas pour figer la solution. Options repérées à l'audit :

- **Copie figée versionnée** : déployer un snapshot dans
  `~/.local/share/google-mcp/<version>/`, le script de [[0013]] pointant là plutôt
  que sur le clone. Simple, pas de dépendance nouvelle.
- **Clone / worktree dédié au déploiement** : un second répertoire sur un tag,
  jamais touché par le développement. Le moins de code à écrire.
- **Artefact autonome** (venv figé, zipapp Python) : plus étanche, isole aussi les
  dépendances de l'interpréteur.
- **Tag + release, puis install depuis l'artefact** : rejoint [[0020]] — à
  arbitrer pour ne pas construire deux fois la même chose.

Questions ouvertes pour le grooming :

- Quel **geste de déploiement** ? (`gwsa deploy`, un script, un `make install` ?)
  Et qui l'exécute — l'humain, comme les autres gestes machine du projet ?
- Quelle **granularité de version** ? Tag git, `SERVER_VERSION` dérivée du tag,
  horodatage ? Le serveur doit-il annoncer la version réellement déployée ?
- Quel **retour arrière** si une version déployée est mauvaise ?
- Les deux profils cohabitent-ils (un MCP « stable » **et** un MCP « dev » branchés
  en parallèle sous deux noms), ou bascule-t-on de l'un à l'autre ?
- Que devient l'état hors-repo (`~/.config/gws-accounts`, verrous, grants) — partagé
  entre les deux, ou isolé ? **Point sensible** : partager les tokens entre une
  version dev et une version stable réexpose le problème qu'on cherche à fermer.

## Critères d'acceptation

*Esquisse — à confirmer au grooming, pas encore la DoR.*

- [ ] Modifier le code source du clone ne change pas le comportement du MCP utilisé
      par Claude Desktop / Claude Code.
- [ ] Une version déployée est **identifiable** (le serveur annonce la version qu'il
      exécute réellement, plus un `0.1.0` en dur).
- [ ] Déployer une nouvelle version est un geste explicite et reproductible.
- [ ] Le retour à la version précédente est possible.

## Notes

- **Priorité P0 arbitrée par le PO le 2026-07-25** : seule fiche P0 du backlog,
  elle passe devant l'épic [[0017]] et ses enfants (tous P2).
- **Hors épic 0017 délibérément** : il s'agit d'hygiène de développement pour
  l'auteur, pas de généralisation à d'autres utilisateurs.
- **Frontière avec [[0020]]** : ici on découple *le déploiement local de l'auteur*
  du working tree ; là-bas on rend l'installation *distribuable à un tiers*
  (`.mcpb`, releases). Recouvrement réel sur « produire un artefact figé » — si
  cette fiche livre le versionnement, 0020 le réutilise plutôt que de le refaire.
- La fiche [[0013]] n'est pas à rouvrir : son script reste le bon point d'entrée,
  c'est sa **cible** qui doit changer (artefact déployé au lieu du clone).
