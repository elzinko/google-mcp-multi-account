---
id: 0093
title: Cohérence de nommage — relier `mag` / google-multi-account / repo sans casser le MCP
type: feature
priority: P3
version:
epic:
status: todo
ready:
pr:
created: 2026-08-29
---

## Contexte / Problème

Trois familles de noms cohabitent **sans lien visible**, ce qui déroute l'utilisateur :

- **Commande** : `mag`.
- **Produit** : `google-multi-account` (`PRODUCT_SLUG`, `gateway/config.py`) — affiché dans
  l'admin (titre + `h1`), le prompt Touch ID, la doc.
- **Serveur MCP** : `google-multi-account` — c'est la **clé de configuration** des clients
  (Claude Desktop, Cursor…), protégée dans le code (`admin/server.js`, `PROTECTED_MCP_NAMES`).
- **Dépôt** : `google-mcp-multi-account`.

L'utilisateur installe « mag », voit « google-multi-account » dans l'admin, trouve le dépôt
« google-mcp-multi-account » → rien ne dit que c'est le même produit.

**Contrainte dure** : le nom du **serveur MCP** (`google-multi-account`) **ne doit pas être
renommé** — les clients le référencent dans leur config ; le changer **casse toutes les
installations existantes**. Breaking change à éviter (sinon migration lourde, annoncée,
version majeure).

Avoir un nom produit ≠ nom de commande n'est PAS un défaut (cf. `ripgrep`/`rg`,
`GitHub CLI`/`gh`). Le trou, c'est l'absence de **lien** entre les noms.

## Proposition (à groomer)

Cohérence par le **lien** et la **doc**, pas par un renommage :

- **Admin** : afficher `mag` à côté du titre (ex. « google-multi-account — piloté par `mag` »)
  pour que l'utilisateur fasse le pont install ↔ commande.
- **README / doc** : une phrase de correspondance — « produit **google-multi-account**,
  dépôt **google-mcp-multi-account**, commande **mag** ».
- **App OAuth** : nommer l'écran de consentement « mag » (geste console, cf. [[0090]]).
- **Ne pas** renommer le serveur MCP ni `PRODUCT_SLUG` (source du nom MCP) sans migration
  dédiée, annoncée, majeure.

## Critères d'acceptation (à affiner)

- L'admin relie visiblement `mag` et `google-multi-account`.
- Le README explicite la correspondance produit / dépôt / commande.
- Le nom du serveur MCP reste `google-multi-account` (aucune régression de config client).

## Notes

- Sujet de marque / cohérence, **pas un bug**. Confort, faible risque — sauf le piège MCP.
- Débat différé au grooming : aligner le nom produit sur le dépôt (ajouter « mcp ») —
  **rejeté par défaut** car `PRODUCT_SLUG` alimente le nom MCP (breaking).
- Croise [[0090]] (nom de l'app OAuth) et [[0092]] (nom de commande `mag`).
