---
id: 0039
title: Bannir « jeton/token » des surfaces utilisateur — un seul vocabulaire (accès / connexion)
type: chore
priority: P2
version:
epic:
status: idea
ready:
pr:
created: 2026-07-27
---

## Contexte / Problème

Retour utilisateur (2026-07-27) sur la maquette admin : « à quoi sert ce
jeton ? c'est très confus. C'est un produit simple pourtant ! ». Le mot
« jeton » est de la plomberie OAuth qui a fui dans l'interface.

Un panel de nommage (lentilles novice / exactitude / cohérence) a tranché un
lexique à **deux familles de mots, jamais mélangées** :

| Idée | Mots retenus |
|---|---|
| L'accès (quotidien, choix humain) | 🔒 Accès verrouillé · Déverrouiller (30 min)… · 🔓 Déverrouillé · encore N min · Reverrouiller |
| La connexion à Google (panne rare) | ⚠️ Connexion à refaire · Refaire la connexion… |
| Destructeur (zone de danger) | Retirer ce compte de l'outil |

La maquette v10 applique ce lexique. Mais le panel a repéré que le mot
« jeton/token » **resurgira par le chat** tant que les autres surfaces ne
suivent pas :

- `CLAUDE.md` : « erreur exit code 2 (auth) → **token expiré** » — l'agent
  répète ce mot à l'utilisateur.
- Messages d'erreur côté gateway/broker et textes `access_request`.
- `gwsa list` / sorties CLI destinées à être lues par l'humain.
- Docs (`docs/usage.md`, `SECURITY.md`, protocole des tests manuels).

## Proposition

- Remplacer « token/jeton expiré » par « **connexion à Google expirée — à
  refaire** » dans toutes les surfaces lues par l'humain (messages MCP,
  CLAUDE.md, docs, sorties gwsa).
- Ajouter une ligne de glossaire dans SECURITY.md : « verrou (CLI lock/unlock)
  = accès verrouillé dans l'interface ; jeton OAuth = la “connexion” dans
  l'interface » — pour que le CLI expert et les docs techniques gardent leur
  précision sans créer un 3ᵉ vocabulaire.
- Interdits dans l'UI et les messages destinés à l'humain : « jeton »,
  « OAuth », « token ».

## Critères d'acceptation

- [ ] À groomer.

## Notes

- Découle de la maquette v10 (`docs/design/admin-cards-v10.html`) et du panel
  de nommage. Garde-fous complets du panel consignés dans le commit v10.
- Le mot « verrouillé » est **conservé** partout : le chat dit déjà « profil
  verrouillé » (refus MCP), le CLI dit lock/unlock, Touch ID aussi. Le
  problème n'a jamais été le verrou — c'était le jeton.
- **Partiel après #48** : les cartes admin n'utilisent plus « jeton » ; restent
  « tokens » (dialog déconnexion), bouton « Setup OAuth », et docs/CLI/CLAUDE.md
  — c'est le reste de *cette* fiche, pas à shipper encore.
