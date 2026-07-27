---
id: 0032
title: La notification Touch ID doit nommer le compte et le produit, pas l'alias seul
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

Constaté pendant le test manuel drive-2-comptes (2026-07-27). Au moment de
poser le doigt, la boîte système Touch ID affiche l'**alias**, jamais l'email :

| Geste | Texte affiché |
|---|---|
| unlock | `déverrouiller le profil Google « perso »` |
| grant | `autoriser l'écriture Drive sous « ZZ-TESTS » (perso, 2 h)` |
| add | `connecter un nouveau compte Google « perso »` |

Deux manques au moment du consentement :

1. **Le compte n'est pas prouvé.** « perso » est un surnom choisi il y a des
   semaines ; il ne dit pas *quel* compte Google on déverrouille. L'email,
   lui, est sans ambiguïté — et il est déjà lisible sans exécuter `gws`, même
   profil verrouillé (`.email`, ADR-0002).
2. **L'origine est fausse.** La boîte nomme le processus demandeur, qui est
   `/usr/bin/swift` (`scripts/touchid.swift`). macOS affiche donc « swift »,
   pas « google-mcp-multi-account ». Aucune provenance produit — un même
   dialogue « swift » pourrait venir de n'importe quoi.

## Proposition

- Ajouter l'email au texte : `déverrouiller « perso » (thomas.couderc@gmail.com)`.
  La donnée existe déjà via `_profile_email` / `.email`.
- Étudier ce qui peut porter une identité produit dans le dialogue système
  (nom du binaire signé, `localizedReason` enrichi). La provenance dure relève
  de la fiche 0001 (signature) ; ici, viser au moins que le texte cite
  « google-mcp-multi-account ».

## Critères d'acceptation

- [ ] À groomer.

## Notes

- Règle dégagée au passage : l'alias est la **clé** (nom de répertoire, court,
  stable à travers une reconnexion) ; mais partout où l'humain **consent**
  (Touch ID, confirmation, journal), c'est le **compte** qui doit être nommé.
  `gwsa list` respecte déjà ça (alias + email) ; le Touch ID l'a oublié.
- Voir [[0033-grant-one-shot-depuis-conversation]] (même surface de confiance)
  et la fiche 0001 (élicitation signée, provenance dure).
