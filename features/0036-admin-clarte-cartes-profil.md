---
id: 0036
title: Clarté des cartes profil dans l'admin (état d'accès, badges, hiérarchie des actions)
type: feature
priority: P2
version:
epic:
status: idea
ready:
pr:
created: 2026-07-27
---

## Contexte / Problème

Revue UX des cartes profil de l'admin (capture du 2026-07-27). Les cartes
mélangent deux axes — la **connexion** (le token OAuth est-il valide ?) et
l'**accès** (un LLM peut-il lire/écrire maintenant ?) — sans les distinguer,
ce qui rend l'état difficile à lire d'un coup d'œil.

Findings (état rendu par `admin/index.html`, lignes ~348-362) :

1. **Deux états opposés, badges jumeaux.** « accès sur demande » (verrouillé,
   fermé) et « encore N min » (déverrouillé, ouvert, compte à rebours) sont
   **contraires** mais se ressemblent (même famille d'icône cadenas, même
   pastille). Impossible de repérer en un instant *quels comptes sont ouverts*.

2. **« accès sur demande » décrit la règle, pas l'état.** C'est la politique
   (« l'accès se demande »), pas l'état courant (« verrouillé »). Collé au
   badge vert « connecté », un nouvel arrivant ne sait pas si c'est bon ou
   mauvais. Mieux : un mot d'état clair (« 🔒 Verrouillé ») + « accès sur
   demande » en sous-titre/infobulle.

3. **Deux axes présentés comme des pastilles sœurs.** « connecté » (auth) et le
   badge de verrou (accès) répondent à deux questions différentes ; les aligner
   comme des égales brouille la lecture. Piste : « Connexion : ✅ » d'un côté,
   « Accès : 🔒 verrouillé » de l'autre.

4. **« Déverrouiller… » affiché même sur un compte déjà ouvert.** Pour un compte
   « encore N min », proposer « Déverrouiller… » interroge (c'est déjà ouvert).
   Si l'intention est de prolonger, l'appeler « Prolonger… ». « Déverrouiller… »
   ne garder que sur les comptes fermés.

5. **« Révoquer » (rouge, destructif) est l'ancre visuelle.** Le rouge attire le
   plus l'œil alors que c'est l'action la plus rare (déconnecter le compte). Une
   action destructrice ne doit pas dominer : la démoter (icône, menu overflow),
   la sortir de la rangée principale.

6. **Compteur de zones cryptique.** « (0) » et « (0 + 1 temp) » ne se lisent
   pas. Mieux : « Zones : 0 permanente · 1 temporaire ».

7. **Aucune hiérarchie au repos.** Les cinq cartes ont le même poids visuel.
   Le compte *ouvert* (déverrouillé) est justement l'état « chaud » qu'on veut
   repérer : lui donner un accent (bordure gauche colorée) le ferait ressortir.

## Proposition

Restructurer la carte autour de deux lignes d'état lisibles (Connexion / Accès),
un mot d'état clair plutôt qu'une phrase de politique, des zones énoncées en
clair, les actions destructrices démotées, et un accent visuel sur les comptes
ouverts. Maquette avant/après à produire au grooming.

## Critères d'acceptation

- [ ] À groomer.

## Notes

- Revue déclenchée par une question utilisateur (« l'UI n'est pas super
  claire »). Complémentaire de [[0035-admin-acces-rapide-et-visu-zones]]
  (accès à l'admin) — ici c'est la **lisibilité une fois dedans**.
- Respecter le design system s'il existe (`docs/design-system.md`) ; sinon,
  rester sobre, cohérent avec l'existant.
