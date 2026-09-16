---
id: "20260916201419331"
title: Exposer la pagination (pageToken) dans gmail_list pour parcourir tout l'historique
type: feature
priority: P2
product: google-multi-account
version:
epic:
status: idea
ready:
pr:
created: 2026-09-16
---

## En clair

Aujourd'hui `gmail_list` s'arrête aux premiers messages et ne sait pas dire « page
suivante ». Du coup, impossible de parcourir tout un historique de mails. L'API Gmail
sait pourtant le faire : elle renvoie un curseur qu'on lui redonne pour la page d'après.
Cette fiche expose ce curseur, sans rien changer d'autre.

Idée reversée depuis la PR #86 (fermée) — ancienne fiche `0075` au format pré-Skema-v2.

## Contexte / Problème

L'outil MCP `gmail_list` s'arrête à un lot de messages. Il n'y a aucun moyen de demander
« la page suivante ». Résultat : impossible de parcourir un historique de mails complet.

L'API Gmail sait le faire. Sa réponse `users.messages.list` contient déjà un curseur
`nextPageToken` : on le renvoie à l'appel suivant pour obtenir la page d'après. Notre outil
ne l'expose ni en entrée ni en sortie — le curseur est perdu à chaque appel.

La lecture nécessaire existe déjà : `gmail_list(alias, query, max_results)` accepte un
`query` (donc `from:me after:...`) et `gmail_get` récupère le détail. Rien à réécrire côté
lecture — il manque seulement la pagination.

## Proposition

Étendre `gmail_list` sans rien casser :

- **entrée** : un paramètre `page_token` optionnel, passé tel quel à l'API Gmail
  (`params.pageToken`) ;
- **sortie** : laisser passer le `nextPageToken` déjà présent dans la réponse Gmail
  (vérifier qu'il n'est pas filtré au passage) ;
- **inchangé** : mêmes scopes, même policy, même périmètre de lecture. Seule la fenêtre de
  parcours s'élargit. Sans `page_token`, le comportement reste identique à aujourd'hui.

Le modèle existe déjà dans le code : `drive_permissions_list` expose `page_token` en entrée
et `nextPageToken` en sortie (`gateway/api.py`). Cette fiche applique le même patron à
`gmail_list`.

## Critères d'acceptation

- [ ] `gmail_list` accepte `page_token` et renvoie `nextPageToken` quand l'API Gmail en
      fournit un.
- [ ] Sans `page_token`, comportement strictement inchangé (compatibilité).
- [ ] La doc de l'outil (surface MCP) mentionne les deux nouveaux champs.

## Comment vérifier

- **Test hermétique** : appeler `gmail_list` avec un `page_token` bidon via le harnais de
  test (comptes simulés, `scripts/test.sh`) → vérifier que `pageToken` est bien transmis
  dans les params de la requête, et que `nextPageToken` de la réponse ressort au niveau du
  résultat de l'outil.
- **Non-régression** : un appel `gmail_list` sans `page_token` renvoie exactement la même
  forme qu'avant (aucun champ retiré, ordre inchangé).
- **Surface MCP** : `page_token` et `nextPageToken` apparaissent dans la description de
  l'outil (`gateway/mcp_server.py`), comme pour `drive_permissions_list`.

## Notes — d'où vient la demande

Un autre projet, `elzinko` (un outil qui réécrit des textes « dans mon style »), veut lire
mes anciens mails écrits par moi pour s'en servir d'exemples. Il réutilise ce connecteur
tel quel, lancé comme sous-processus, sans y toucher. Pour construire son corpus, il doit
balayer tout l'historique — pas seulement les derniers messages —, d'où le besoin de
pagination.

Pas urgent : priorité **P2**, petit et sans risque. À planifier quand ce projet
consommateur démarrera cette phase.
