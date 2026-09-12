---
id: 0075
title: Exposer la pagination (pageToken) dans gmail_list pour parcourir tout l'historique
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

Aujourd'hui, l'outil MCP `gmail_list` s'arrête à 50 messages. Il n'y a aucun
moyen de demander « la page suivante ». Résultat : impossible de parcourir un
historique de mails complet.

Pourtant l'API Gmail sait le faire. Sa réponse `users.messages.list` contient
déjà un curseur `nextPageToken` : on le renvoie à l'appel suivant pour obtenir
la page d'après. Notre outil ne l'expose ni en entrée ni en sortie — le curseur
est perdu à chaque appel.

La lecture nécessaire, elle, existe déjà : `gmail_list(alias, query, max_results)`
accepte un `query` (donc `from:me after:...`) et `gmail_get` récupère le détail.
Rien à réécrire côté lecture — il manque seulement la pagination.

## Proposition

Étendre `gmail_list` sans rien casser :

- **entrée** : un paramètre `page_token` optionnel, passé tel quel à l'API
  Gmail (`params.pageToken`) ;
- **sortie** : laisser passer le `nextPageToken` déjà présent dans la réponse
  Gmail (vérifier qu'il n'est pas filtré au passage) ;
- **inchangé** : mêmes scopes, même policy, même périmètre de lecture. Seule la
  fenêtre de parcours s'élargit. Sans `page_token`, le comportement reste
  identique à aujourd'hui.

## Critères d'acceptation

- [ ] `gmail_list` accepte `page_token` et renvoie `nextPageToken` quand l'API
      Gmail en fournit un.
- [ ] Sans `page_token`, comportement strictement inchangé (compatibilité).
- [ ] La doc de l'outil (surface MCP) mentionne les deux nouveaux champs.

## Notes — d'où vient la demande

Un autre projet, `elzinko` (un outil qui réécrit des textes « dans mon style »),
veut lire mes anciens mails écrits par moi pour s'en servir d'exemples. Il
réutilise ce connecteur tel quel, en le lançant comme sous-processus, sans y
toucher. Pour construire son corpus, il doit balayer tout l'historique — pas
seulement les 50 derniers messages —, d'où le besoin de pagination.

Pas urgent : priorité **P2**, petit et sans risque. À planifier quand ce projet
consommateur démarrera cette phase.

> Renumérotée `0073 → 0075` : l'id `0073` était déjà réservé par la PR #82
> (transfert de propriété Drive), créée avant celle-ci.
