---
id: 0032
title: La notification Touch ID doit nommer le compte et le produit, pas l'alias seul
type: feature
priority: P2
version:
epic:
status: shipped
ready: 2026-07-28
pr: "#48"
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

- Ajouter l'email au texte : `déverrouiller « perso » (perso@example.com)`.
  La donnée existe déjà via `_profile_email` / `.email`.
- Étudier ce qui peut porter une identité produit dans le dialogue système
  (nom du binaire signé, `localizedReason` enrichi). La provenance dure relève
  de la fiche 0001 (signature) ; ici, viser au moins que le texte cite
  « google-mcp-multi-account ».

## Livré (PR #48, précisé #50)

- unlock / grant : `strong_auth_reason` affiche l'**email** (pas l'alias) —
  ex. `déverrouiller le compte Google thomas@…`
- Binaire compilé nommé `bin/mcp-google-mcp-multi-account` (macOS n'affiche
  plus « swift » / `swift-frontend` comme demandeur)
- `gwsa add` : si strongauth est actif, l'**email est requis**
  (`gwsa add <alias> <email>`) — Touch ID cite cet email, plus jamais l'alias
  seul (avant connexion il n'y a pas encore de `.email`)
- Formule retenue : email d'abord (sans « alias + email ») — l'intention
  « nommer le compte » est couverte ; la signature dure reste fiche 0001

## Critères d'acceptation

- [x] La raison Touch ID cite l'email du compte (pas seulement l'alias) —
      unlock/grant via `.email` ; add via email-attendu obligatoire sous
      strongauth
- [x] Le dialogue système nomme un binaire produit (`mcp-google-mcp-multi-account`),
      pas `swift`

## Notes

- Règle dégagée au passage : l'alias est la **clé** (nom de répertoire, court,
  stable à travers une reconnexion) ; mais partout où l'humain **consent**
  (Touch ID, confirmation, journal), c'est le **compte** qui doit être nommé.
  `gwsa list` respecte déjà ça (alias + email) ; le Touch ID l'a oublié.
- Voir fiche 0001 (élicitation signée, provenance dure).
