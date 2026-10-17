---
id: "20261003012132100"
title: Le consentement en conversation nomme le composant (« swift-frontend ») au lieu du produit
type: bug
priority: P2
product: google-multi-account
version:
epic: 0082
status: idea
ready:
pr:
created: 2026-10-03
---

## En clair

Quand on ouvre ou déverrouille une session **depuis le chat**, le popup Touch ID
s'intitule « swift-frontend » — le nom d'un composant interne, pas celui du produit.
L'humain lit ce popup pour savoir ce qu'il autorise ; un nom interne brouille ce repère.
Un correctif existait déjà pour les autres dialogues Touch ID ; le nouveau chemin
« en conversation » ne l'a pas repris.

## Contexte / problème

Constaté le 2026-10-03, en testant gmail-cleanerz contre google-multi-account v1.2.0.

Les popups déclenchés par `session_open_in_conversation` et
`session_unlock_in_conversation` s'affichent sous le titre « swift-frontend » :

- « "swift-frontend" souhaite mag : session_open — . »
- « "swift-frontend" souhaite mag : déverrouiller "perso" … pour la session … (60 min). »

Un correctif antérieur faisait déjà **nommer le produit** dans les dialogues Touch ID :

- fix(elicitation) : dialogue Touch ID strongauth nomme le produit (PR #74, fiche 0044)
- fix(iam) : dialogue Touch ID de « Réparer l'accès » nomme le produit

Ces correctifs visaient l'authentification et la réparation d'accès. Les outils
*in-conversation* sont arrivés après et affichent encore le nom brut du composant Swift.
Ce n'est donc pas la même régression qui revient : c'est un **nouveau chemin qui n'a
pas hérité du nommage**.

## Proposition

Faire nommer le **produit** et l'acte demandé dans les popups des outils in-conversation,
comme pour les autres dialogues Touch ID. Réutiliser le mécanisme de la PR #74 plutôt que
de redéfinir une chaîne en double.

## Critères d'acceptation

- [ ] Le popup de `session_open_in_conversation` nomme le produit, pas « swift-frontend ».
- [ ] Idem pour `session_unlock_in_conversation`.
- [ ] Le nom affiché passe par le même mécanisme que les dialogues déjà corrigés (pas de
      chaîne dupliquée).
- [ ] Test manuel (vrais comptes, Touch ID) : capture avant / après du popup.

## Comment vérifier

Activer le mode opt-in, puis déclencher depuis une conversation un
`session_open_in_conversation` suivi d'un `session_unlock_in_conversation`. Lire le titre
du popup : il nomme le produit et l'acte, et plus « swift-frontend ».

## Notes

Touche le popup Swift `scripts/elicitation-sign.swift` (titre / texte) et le chemin
d'élicitation in-conversation côté `gateway/`.

Prior art : PR #74 (dialogue strongauth nomme le produit), fiches 0043 / 0044.

Fiche sœur (même popup Swift, épic 0082) :
[Popup Touch ID à deux boutons « Une fois / Pour la session »](20260922221816747_popup-swift-deux-boutons-portee.md)

Découvert en testant gmail-cleanerz (session 2026-10-03).
