---
id: 0091
title: Updater — rollback ergonomique : commande revert, messages CLI, help enrichi
type: feature
priority: P2
version:
epic:
status: todo
ready: 2026-09-04
pr:
created: 2026-08-29
---

## En clair

Le retour en arrière existe (`mag update --to <version>`), mais c'est austère : il faut connaître
le tag exact. On ajoute l'**ergonomie** : une commande `mag revert` (« reviens à la version
précédente »), un message après chaque mise à jour qui rappelle comment revenir, et un `--help`
qui documente enfin le rollback. S'appuie sur le socle 0081 (helper de re-ciblage des liens).

## Contexte / Problème

Le rollback existe déjà (`mag update --to <version>`), et les versions sont figées dans
`~/.local/share/google-mcp/` avec un lien `current` — un vrai schéma **blue-green**. Mais
l'ergonomie manque :

- **Pas de raccourci** « reviens à la version précédente » : il faut connaître le tag
  exact et taper `--to vX.Y.Z`.
- **Les messages de l'updater n'expliquent pas** comment revenir en arrière après une mise à jour.
- **Le `help` de `update`** ne documente ni `--to` ni le rollback.

Constaté 2026-08-29 : l'utilisateur veut « un truc de pro » où l'on peut revenir en
arrière vite si une migration rate.

## Proposition (à groomer)

- **Commande `mag revert`** (ou `mag update --rollback`) : rebascule `current` sur la
  **version précédente** déployée, et re-cible les liens PATH (réutilise le helper
  partagé de [[0081]]).
  - **« Précédente » définie sans ambiguïté (tranché au grooming 2026-09-04)** : poser un
    lien `previous` à chaque bascule de `current` — simple, non ambigu, sans tri d'historique
    à parser. `mag revert` rebascule `current` sur `previous`.
  - **Croiser [[0028]]** (ménage des versions déployées) : la cible du revert peut avoir
    été purgée → gérer proprement le cas « aucune version précédente disponible ».
- **Message post-update** : après un `update` réussi, afficher une ligne
  « Pour revenir en arrière : `mag update --to <version précédente>` (ou `mag revert`) ».
- **Help enrichi** : `mag update --help` documente `--check`, `--to <version>`, le
  rollback, et donne un exemple.

## Critères d'acceptation (BDD, à affiner)

- **Given** au moins deux versions déployées **non purgées** **When** `mag revert`
  **Then** `current` pointe sur la version précédente définie, et **`mag` reste
  invocable** (+ `gma`/`gwsa` en repli **rollback interne** — cf. [[0081]] et [[0092]]
  pour la distinction lien exposé ↔ repli).
- **Given** un `mag update` qui vient de réussir **Then** la sortie indique comment
  revenir en arrière.
- **Given** `mag update --help` **Then** `--to` et le rollback sont documentés avec un exemple.

## Comment vérifier

Avec ≥ 2 versions déployées non purgées : `mag revert` rebascule `current` sur `previous`, et
`mag` reste invocable. Après un `mag update` réussi : la sortie indique comment revenir en
arrière. `mag update --help` documente `--to` et le rollback avec un exemple. Cas « aucune
version précédente » (purgée par [[0028]]) : message clair, pas de casse.

## Notes

- **Ne remplace pas** [[0081]] : celle-ci corrige les **bugs** de rollback à travers le
  renommage (liens cassés) ; 0091 ajoute l'**ergonomie**. Dépend du helper de re-ciblage
  de 0081.
- **Cluster updater/renommage** : [[0081]] (bugs rollback), 0091 (ergonomie), [[0092]]
  (bascule gwsa→mag), [[0028]] (rétention). À regrouper sous un épic commun au grooming —
  sinon `ezk-backlog next` peut tirer 0091 avant que 0081 livre le helper partagé.
