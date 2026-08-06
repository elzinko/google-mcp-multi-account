---
id: 0073
title: Exposer la pagination (pageToken) dans gmail_list pour l'ingestion incrémentale d'elzinko
type: feature
priority: P2
version:
epic:
status: todo
ready:
pr:
created: 2026-08-06
---

## Contexte / Problème

Le projet `elzinko/elzinko` (reformulation « dans mon style ») veut ingérer mes
mails **écrits par moi** comme corpus, en réutilisant CE connecteur tel quel en
sous-processus stdio (adaptateur `McpClientSource`, fiches elzinko 0003/0004) —
avec les profils multi-comptes par alias et la policy default-deny inchangés.

La lecture nécessaire existe déjà : `gmail_list(alias, query, max_results)`
accepte `query` (donc `from:me after:...`) et `gmail_get` récupère le détail —
**aucune réécriture nécessaire**. Mais `gmail_list` plafonne à 50 résultats et
n'expose ni `pageToken` en entrée ni `nextPageToken` en sortie (l'API Gmail les
fournit) : impossible de balayer un historique complet, et l'ingestion
**incrémentale par curseur** (elzinko fiche 0008, ADR-0008 : rejouable,
idempotente, sans tout re-lire) n'a pas de point d'appui.

## Proposition

Étendre `gmail_list` sans rien casser :

- entrée : `page_token: string` optionnel, passé tel quel à l'API Gmail
  (`params.pageToken`) ;
- sortie : laisser passer `nextPageToken` déjà présent dans la réponse
  `users.messages.list` (vérifier qu'il n'est pas filtré) ;
- la policy et les scopes sont inchangés : même endpoint, même périmètre de
  lecture, seule la fenêtre de parcours change.

Côté elzinko, le curseur persisté sera `(query, nextPageToken)` ou la date du
dernier mail vu (`after:`) — les deux marchent dès que la pagination sort.

## Critères d'acceptation

- [ ] `gmail_list` accepte `page_token` et renvoie `nextPageToken` quand l'API
      Gmail en fournit un.
- [ ] Comportement actuel inchangé sans `page_token` (compatibilité).
- [ ] Doc de l'outil mise à jour (surface MCP).

## Notes

Consommateur demandeur : `elzinko/elzinko` — Phase 2 (fiche 0004
`gmail-drive-multicomptes`, fiche 0008 curseurs). Pas urgent tant que la Phase 2
n'a pas démarré, mais petit et sans risque.
