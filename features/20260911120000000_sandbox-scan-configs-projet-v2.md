---
id: 20260911120000000
title: Sandbox v2 — scanner les configs projet Claude Code / Cursor
type: feature
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

`mag sandbox list` (fiche 0046, v1 livrée) inventorie les entrées MCP au niveau **global**
(Claude Desktop, Cursor global). Il ne regarde pas les configs **de projet** (Claude Code
`.mcp.json` par dépôt, Cursor projet). Résultat : une sandbox branchée sur un projet donné
peut ne pas apparaître dans `list`/`status`. Cette fiche ajoute ce scan.

Origine : dernier item non coché du v1 de la fiche [[0046]], explicitement marqué « (v2) ».

## Contexte / problème

- `scripts/sandbox.sh` (v1) scanne les configs clients globales.
- Les clients supportent aussi des configs **par projet** (ex. `.mcp.json` à la racine d'un
  dépôt pour Claude Code). Une entrée sandbox branchée là est invisible pour `list`/`status`.

## Proposition

- `mag sandbox list` / `status` : détecter aussi les entrées MCP suffixées
  (`google-multi-account-<id>`) dans les configs **projet** connues (au minimum le dépôt
  courant, éventuellement une liste de chemins fournie).
- `wire` / `wire --remove` : cibler une config projet si pertinent (à cadrer au grooming —
  ne pas complexifier le cas courant).

## Critères d'acceptation (à affiner)

- [ ] `mag sandbox list` mentionne une entrée sandbox branchée dans un `.mcp.json` de projet
      (au moins le dépôt courant).
- [ ] Aucune régression du scan global existant ; l'entrée stable `google-multi-account`
      reste intouchée.
- [ ] Tests hermétiques (config projet simulée dans un dossier temporaire).

## Notes

- Découle de [[0046]] (sandbox deploy CLI v1). Faible priorité (confort dogfood).
