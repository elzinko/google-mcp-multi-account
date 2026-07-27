---
id: 0037
title: Sémantique de la suppression en zone — corbeille = suppression, racine de zone immuable, avertissement
type: feature
priority: P1
version:
epic:
status: todo
ready:
pr:
created: 2026-07-27
---

## Contexte / Problème

Incohérence relevée par l'utilisateur (2026-07-27), et déjà signalée comme
**question ouverte** par la fiche 0002 (shipped) : dans le modèle par zones, on
exige que le dossier de zone soit **créé à la main par l'humain**… mais une fois
la zone accordée, le LLM peut **mettre à la corbeille** ce dossier et tout son
contenu.

Cause technique (`scripts/policy-check.py`) : la corbeille se fait par
`drive files update` avec `{"trashed": true}` dans le corps. Le contrôleur
classe l'action d'après le **nom de méthode** (`update`), sans regarder le
corps — donc c'est vu comme une *modification*, autorisée même avec
`delete: false`. La suppression définitive, elle, est bien bloquée
(`delete: false` + `emptyTrash` toujours refusé).

Deuxième effet : la **racine de zone** elle-même compte comme « dans la zone »
(`under_allowed` renvoie vrai pour l'id exact accordé), donc le LLM peut
corbeiller le dossier-frontière, pas seulement son contenu.

Le modèle mental attendu (utilisateur) : l'humain crée le dossier (la
frontière), le LLM travaille **dedans** sans pouvoir supprimer, et « retirer
une zone » est un geste de **config** (`gwsa grant revoke`), jamais une
suppression Drive. Ce dernier point est **déjà vrai** — revoke n'édite que la
config. Il manque de rendre le reste cohérent.

## Proposition (à trancher — options)

**A. Corbeille = suppression (recommandé).** Regarder le corps : un
`{"trashed": true}` est reclassé en catégorie `delete`. Avec le défaut
`delete: false`, le LLM ne peut alors corbeiller **ni** le contenu **ni** la
racine. Le nettoyage redevient un geste humain (ou exige une zone
`delete: true` explicite). Ferme la question ouverte de la fiche 0002.

**B. Racine de zone immuable (à faire dans tous les cas).** Le dossier-
frontière ne peut jamais être corbeillé / renommé / sorti de sa zone, même avec
`delete: true` — seul son contenu est modifiable. `under_allowed` doit
distinguer « est la racine » de « est un descendant ».

**C. Avertissement à la pose d'une zone.** La vue d'ajout de zone doit dire, en
clair (message rouge / séquence explicite), ce qu'accorder une zone implique
selon le modèle retenu. Principe à afficher : **« n'accordez une zone que sur un
dossier que vous acceptez de confier »**.

**D. (extension future) Mode par provenance.** Le LLM ne touche que ce qu'il a
créé (marqueur `appProperties` posé à la création, vérifié avant modif/
corbeille). Plus fin, plus lourd (lecture API par opération) ; à garder en
réserve, pas pour la v1.

## Critères d'acceptation

- [ ] À groomer — décision PO sur A (corbeille = delete ?) attendue en premier.
- [ ] B livré quoi qu'il arrive : la racine de zone est intouchable.
- [ ] C : l'avertissement apparaît dans le flux d'ajout de zone (admin).
- [ ] Test hermétique : `files update {trashed:true}` refusé si `delete:false`
      (option A) ; racine de zone jamais corbeillable (option B).

## Notes

- Tranche la question laissée ouverte par la fiche 0002 (« files update avec
  {trashed:true} classé update… à trancher »).
- Impact sur le protocole de test manuel (fiche 0034) : la phase de nettoyage
  par corbeille deviendrait un geste humain, ou exigerait une zone delete:true.
- Voir [[0038-creer-dossier-zone-rapidement]] (le pendant : créer la frontière
  sans friction, côté humain).
