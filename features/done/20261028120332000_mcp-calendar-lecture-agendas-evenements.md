---
id: "20261028120332000"
title: Exposer Google Calendar en lecture via MCP — lister les agendas et les événements
type: feature
priority: P2
product: google-mcp-multi-account
version:
epic: "0021"
status: shipped
ready: 2026-10-28
pr: "local (d4d085c)"
created: 2026-10-28
---

## En clair

Le serveur MCP de ce projet ne sait lire que Gmail et Drive. Un agent ne peut pas
encore **voir ton agenda**. On ajoute deux outils en **lecture seule** : lister tes
agendas, et lister les événements d'un agenda. Aucun écriture, aucun envoi.

Première tranche de l'épic [Élargir la couverture MCP](0021-couverture-mcp-elargie.md)
(Calendar, Docs, Sheets, Tasks). On commence par Calendar en lecture, car toute la
sécurité est **déjà posée** : la policy par défaut autorise `calendar.read`, et la
couche de catégorisation sait déjà classer les appels Calendar. Il ne manquait que les
outils eux-mêmes.

## Contexte / problème

Chaque outil MCP (`gmail_list`, `drive_list`…) est une entrée de la liste `TOOLS`
(`gateway/mcp_server.py`) plus un handler (`gateway/api.py`) qui construit la commande
`gws` et la passe au point unique `_run(alias, gws_args, session=…)`. Ce point unique
applique la policy (default-deny), le gate transactionnel et le journal.

Pour Calendar, cette plomberie est **prête** mais inutilisée :

- `gateway/default_policy.py` déclare déjà `calendar: {read: True, …}`.
- `gateway/categorize.py` classe déjà `calendar events list` et `calendar calendarList
  list` en `read`.
- `scripts/test.sh` teste déjà « calendar events list — lecture autorisée ».

Aucun outil `calendar_*` n'existe pourtant dans `TOOLS`. L'agent ne peut donc pas lire
l'agenda, alors que la permission et le classement sont déjà en place.

## Proposition

Deux outils MCP en **lecture seule**, calqués sur `gmail_list` :

- **`calendar_calendars_list`** — liste les agendas du compte (`calendarList.list`).
  Sert à découvrir l'`id` d'un agenda.
- **`calendar_events_list`** — liste les événements d'un agenda (`events.list`).
  `calendar_id` par défaut `primary` ; par défaut, les événements **à venir**
  (`timeMin` = maintenant), triés par date de début.

Les deux passent par `_run` sans rien changer à la sécurité : la policy
`calendar.read` (déjà `True` par défaut) les autorise, un service refusé reste refusé.
Aucun outil d'écriture, de création ni de partage dans cette tranche.

## Critères d'acceptation

- [ ] Les deux outils apparaissent dans la liste des outils MCP (`tools/list`).
- [ ] `calendar_calendars_list` appelle `gws calendar calendarList list` et rend
  `{ok, alias, result}`.
- [ ] `calendar_events_list` appelle `gws calendar events list` avec `calendarId`
  (défaut `primary`) dans les params, et rend `{ok, alias, result}`.
- [ ] Le jeton de session est transmis à `_run` (comme les outils Gmail/Drive).
- [ ] Un profil dont la policy refuse `calendar.read` voit l'appel refusé (gate
  inchangé) — couvert par le test de policy existant.
- [ ] Aucune dépendance ajoutée ; aucun outil d'écriture exposé.

## Comment vérifier

Suite hermétique (sans comptes réels) :

```bash
./scripts/test.sh
```

Le test monkeypatch `api._run`, appelle `api.calendar_calendars_list(...)` et
`api.calendar_events_list(...)`, puis vérifie les `gws_args` construits et la structure
rendue. Il vérifie aussi que les deux noms sont présents dans `mcp_server.TOOLS` et
routés par `DISPATCH`. Avant l'implémentation, l'appel aux handlers lève
`AttributeError` : le test échoue (preuve qu'il teste bien le neuf).

Bout en bout (compte réel, manuel) : dans une conversation MCP, demander « liste mes
agendas » puis « qu'est-ce que j'ai cette semaine sur l'agenda principal ? » — les deux
outils répondent en lecture, sans popup d'écriture.
