---
id: "20260906234210000"
title: Sessions — purger les sessions vides + expiration automatique
type: feature
priority: P3
product: google-mcp-multi-account
version:
epic: 0060
status: suggest
ready:
pr:
created: 2026-09-06
---

## En clair

La vue Sessions de l'admin annonce des accès « temporaires », mais les sessions vides
s'accumulent sans jamais partir. Au test du 2026-09-06, **18 sessions** étaient présentes,
toutes « aucune capacité accordée », certaines vieilles de plusieurs jours. On propose deux
gestes : un bouton **« purger les sessions sans capacité »**, et une **expiration automatique**
des sessions inactives.

> Trouvée en passe de test (bug-hunt read-only). Statut `suggest` : à valider avant de tirer.
> Rapport de session : `SPRINT.md` (section bug-hunt).

## Contexte / problème

Chaque conversation d'un client MCP ouvre une session. Le sous-titre de la vue Sessions dit
« Les accès donnés ici valent pour **cette conversation seulement**, et sont **temporaires** ».
Or rien ne les enlève : il n'existe qu'une purge **une par une** (« Purger la session »).
Résultat : la grille grossit avec des cartes vides. Deux inconvénients :

- **Bruit** : difficile de repérer les sessions qui ont vraiment des droits parmi les vides.
- **Écart au discours** : « temporaires » alors qu'elles persistent des jours.

À clarifier d'abord : ces sessions vides sont-elles gardées **à dessein** (audit), ou est-ce
un simple manque de ménage ? La réponse oriente la solution (purge manuelle vs expiration).

## Proposition

- Un bouton **« purger les sessions sans capacité »** dans la barre de la vue Sessions
  (action groupée, avec confirmation).
- Une **expiration automatique** des sessions inactives au-delà d'un délai (TTL configurable),
  au moins pour celles qui n'ont **aucune** capacité accordée.
- Laisser intactes les sessions qui portent des droits (elles restent gérées à la main).

## Critères d'acceptation

- [ ] Un geste unique retire toutes les sessions sans capacité (après confirmation).
- [ ] Les sessions inactives sans capacité disparaissent seules au-delà du TTL.
- [ ] Une session portant des droits n'est jamais purgée automatiquement.
- [ ] Rendu clair ET sombre corrects ; zéro dépendance ajoutée.

## Comment vérifier

Ouvrir la vue Sessions avec plusieurs sessions vides. Cliquer « purger les sessions sans
capacité » : seules les vides partent, celles avec droits restent. Laisser une session vide
inactive au-delà du TTL : elle disparaît au rafraîchissement suivant.
