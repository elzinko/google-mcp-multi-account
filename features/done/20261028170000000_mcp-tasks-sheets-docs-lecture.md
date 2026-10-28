---
id: "20261028170000000"
title: Exposer Tasks, Sheets et Docs en lecture via MCP
type: feature
priority: P2
product: google-mcp-multi-account
version:
epic: "0021"
status: shipped
ready: 2026-10-28
pr: "local (9b05ca3)"
created: 2026-10-28
---

## En clair

Le serveur MCP sait lire Gmail, Drive et, depuis peu, l'agenda. Il ne sait pas encore
lire tes **tâches**, tes **feuilles de calcul** ni tes **documents**. On ajoute quatre
outils en **lecture seule** : lister tes listes de tâches, lister les tâches d'une liste,
lire une plage d'une feuille, et récupérer un document. Aucune écriture, aucun envoi.

C'est la suite de la tranche Calendar dans l'épic
[Élargir la couverture MCP](0021-couverture-mcp-elargie.md). Même recette : toute la
sécurité est **déjà posée** (la policy autorise `tasks.read`, `sheets.read`, `docs.read`,
et la catégorisation classe déjà ces lectures en `read`). Il ne manquait que les outils.

## Contexte / problème

Chaque outil MCP (`gmail_list`, `calendar_events_list`…) est une entrée de la liste
`TOOLS` (`gateway/mcp_server.py`) plus un handler (`gateway/api.py`) qui construit la
commande `gws` et la passe au point unique `_run(alias, gws_args, session=…)`. Ce point
unique applique la policy (default-deny), le gate transactionnel et le journal.

Pour Tasks, Sheets et Docs, cette plomberie est **prête** mais inutilisée :

- `gateway/default_policy.py` déclare déjà `tasks`, `sheets`, `docs` avec `read: True` et
  toutes les écritures à `False`.
- `gateway/categorize.py` classe `list`/`get` en `read` par son chemin générique — aucun
  cas particulier à ajouter.

Aucun outil pour ces services n'existe pourtant dans `TOOLS`. Le README promet six
services ; l'agent n'en lisait que trois depuis Claude Desktop.

## Proposition

Quatre outils MCP en **lecture seule**, calqués sur `gmail_list` :

- **`tasks_tasklists_list`** — liste les listes de tâches (`tasklists.list`). Sert à
  découvrir l'`id` d'une liste.
- **`tasks_tasks_list`** — liste les tâches d'une liste (`tasks.list`). `tasklist` par
  défaut `@default` (la liste par défaut du compte) ; par défaut, seules les tâches
  **ouvertes** sont montrées.
- **`sheets_values_read`** — lit une plage de valeurs (`spreadsheets.values.get`).
  `spreadsheet_id` et `range` (ex. `Feuille1!A1:D10`) requis.
- **`docs_get`** — récupère le contenu d'un document (`documents.get`). `document_id`
  requis.

Les quatre passent par `_run` sans rien changer à la sécurité : la policy de lecture (déjà
`True` par défaut) les autorise, un service refusé reste refusé. Les requis manquants sont
refusés **avant** tout appel `gws` (fail-closed). Aucun outil d'écriture, de création ni
de suppression dans cette tranche.

## Critères d'acceptation

- [ ] Les quatre outils apparaissent dans la liste des outils MCP (`tools/list`) et sont
  routés par `DISPATCH`.
- [ ] `tasks_tasklists_list` → `gws tasks tasklists list` ; rend `{ok, alias, result}`.
- [ ] `tasks_tasks_list` → `gws tasks tasks list` avec `tasklist` (défaut `@default`) dans
  les params.
- [ ] `sheets_values_read` → `gws sheets spreadsheets values get` avec `spreadsheetId` +
  `range` ; refuse si l'un des deux manque, sans appeler `gws`.
- [ ] `docs_get` → `gws docs documents get` avec `documentId` ; refuse si vide, sans
  appeler `gws`.
- [ ] Le jeton de session est transmis à `_run` (comme les autres outils).
- [ ] Les quatre opérations restent classées `read` par le gate ; aucun outil d'écriture
  Tasks/Sheets/Docs n'est exposé.
- [ ] Aucune dépendance ajoutée.

## Comment vérifier

Suite hermétique (sans comptes réels) :

```bash
./scripts/test.sh
```

Section « Tasks/Sheets/Docs lecture » : le test monkeypatch `api._run`, appelle les quatre
handlers, puis vérifie les `gws_args` construits, la structure rendue, le refus
fail-closed des requis manquants, la présence des quatre noms dans `mcp_server.TOOLS` +
`DISPATCH`, le routage réel d'un appel, et l'absence de tout outil d'écriture. Avant
l'implémentation, l'appel aux handlers lève `AttributeError` : le test échoue (preuve
qu'il teste bien le neuf).

Bout en bout (compte réel, manuel) : dans une conversation MCP, demander « liste mes
tâches », « lis la plage A1:D10 de cette feuille », « donne-moi le contenu de ce doc » —
les trois répondent en lecture, sans popup d'écriture.
