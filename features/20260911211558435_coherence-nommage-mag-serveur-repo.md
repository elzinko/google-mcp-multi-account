---
id: "20260911211558435"
title: Cohérence de nommage — mag / google-multi-account / repo / GWSA
type: chore
priority: P3
product: google-multi-account
version:
epic:
status: idea
ready:
pr:
created: 2026-09-11
---

## En clair

La même chose porte **quatre noms**, et ça sème la confusion. Il faut décider si on aligne, et
jusqu'où — sachant que renommer le **serveur MCP** casse tous les clients qui pointent dessus.

| Nom | Ce que c'est | Vu par qui |
|---|---|---|
| `mag` | le **CLI** (admin, élicitation, verrous) | l'humain, au terminal |
| `google-multi-account` | le **serveur MCP** | les clients (Claude Desktop/Code : connecteur + serveur local) |
| `google-mcp-multi-account` | le **dépôt / projet** | GitHub, chemins locaux |
| `GWSA_*`, `gws-accounts` | la **plomberie** (env, dossier de config, tokens) | le code, les scripts |

## Contexte / problème

- Le CLI a été renommé **`mag`** (court ; l'ancien `gwsa`/`gma` entrait en collision, ex. l'alias
  oh-my-zsh `gma`). Voir le renommage livré (PR #114).
- Le serveur MCP est resté **`google-multi-account`** **exprès** : le renommer est **breaking**
  (tous les clients — Desktop, Code, et les autres usages du mainteneur — pointent sur ce nom).
  Décision déjà prise à la v1.1.0 : « ne pas renommer le serveur MCP ».
- Le nom du **serveur** a une qualité à préserver : il est **descriptif**. Un client MCP qui
  affiche « google-multi-account » comprend ; « mag » y serait cryptique.
- Le désordre vient surtout du **repo** (`google-mcp-multi-account`) et de l'**infra** (`GWSA_*`),
  pas du couple CLI/serveur en lui-même.

Déclencheur : en branchant le POC « élicitation dans la conversation » sur Claude Desktop, le
mainteneur voit `google-multi-account` partout (connecteur, serveur local) et **aucun** `mag` —
d'où la question « c'est quoi le bon nom du projet ? ».

## Options (à trancher — ne rien casser tant que non décidé)

1. **Statu quo + doc clarifiée** *(coût quasi nul, zéro breaking)*. Garder les quatre noms, mais
   **documenter clairement** la carte des noms (README/doc : `mag` = CLI, `google-multi-account`
   = serveur MCP, etc.). Résout la **confusion** sans toucher au code ni aux clients.
2. **Renommer le repo** *(coût modéré, pas de breaking client)*. `google-mcp-multi-account` → un
   nom cohérent (ex. finissant en `-mcp`). Impact : URL GitHub, chemins, scripts, docs — **pas**
   les configs clients. Réversible.
3. **Renommer le serveur MCP** *(coût élevé, BREAKING)*. `google-multi-account` → un nom aligné
   sur `mag`. Casse tous les clients : chacun doit repointer. Exige une **migration** (alias de
   transition / double-déclaration pendant N versions) et un **rollback** (cf. la contrainte de
   déploiement du projet : `current` → tag). À ne faire que si le gain de cohérence le justifie.
4. **Renommer l'infra `GWSA_*` / `gws-accounts`** *(coût élevé, risqué)*. Touche les variables
   d'environnement, le dossier de config **et les tokens** — fort risque de casse silencieuse.
   Probablement hors périmètre (à laisser tel quel sauf raison forte).

## Recommandation esquissée (à confirmer au grooming)

- **Garder** `google-multi-account` comme nom de serveur (descriptif, stable, breaking à renommer).
- **Garder** `mag` comme CLI (court, pour taper).
- Faire l'**option 1** à coup sûr (doc-carte des noms), peu coûteuse.
- Envisager l'**option 2** (repo) si la cohérence de branding compte.
- **Réserver l'option 3** (serveur) à une vraie refonte, avec migration + rollback planifiés.

## Critères d'acceptation (esquisse — à compléter au grooming)

- [ ] Une **carte des noms** documentée (mag / google-multi-account / repo / GWSA) — qui est quoi,
  vu par qui.
- [ ] Décision tranchée sur chaque option (1 à 4) : faite / rejetée / différée, avec la raison.
- [ ] Si un renommage est retenu : plan de **migration** (alias/compat) + **rollback** explicite,
  et liste des points d'impact (clients, scripts, docs, tokens).
- [ ] Aucun client existant cassé sans migration.

## Comment vérifier

Lire la doc : un nouveau venu comprend en un coup d'œil quel nom désigne quoi. Si un renommage a
lieu, un client configuré sur l'ancien nom continue de marcher (alias) jusqu'à la fin de la
fenêtre de migration, et un rollback ramène l'état antérieur.

## Notes

- Décision antérieure à respecter tant que non rouverte : **ne pas renommer le serveur MCP**
  (breaking) — v1.1.0.
- Purement **branding / lisibilité** : aucune urgence, aucun impact fonctionnel. P3.
- Ne pas confondre avec la dépréciation `gwsa`/`gma` → `mag` (déjà livrée, fiche 0092).
