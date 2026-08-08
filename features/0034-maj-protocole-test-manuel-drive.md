---
id: 0034
title: Mettre à jour le protocole du test manuel drive-2-comptes (limites périmées + nouvelles phases)
type: chore
priority: P3
version:
epic:
status: idea
ready:
pr:
created: 2026-07-27
---

## Contexte / Problème

Le test manuel drive-2-comptes a été rejoué en réel le 2026-07-27 (comptes
`perso` + `mw`). Son `PROTOCOLE.md` a pris du retard sur le code :

1. **« Limites v1 » périmées.** Le protocole affirme « Le serveur MCP n'expose
   ni upload de contenu » — faux depuis la fiche 0024 : `drive_create` accepte
   `content` et convertit le markdown en Google Doc. Le test l'a d'ailleurs
   utilisé, et la conversion a été vérifiée par export (`# ` → vrai titre,
   `**gras**` → gras, listes rendues).
2. **Phases jouées mais non écrites.** Le run a couvert des cas absents du
   protocole, tous concluants :
   - suppression **définitive** refusée (`delete: false`) — barrière ✓
   - création d'un **dossier** `ZZ-TESTS_LLM` refusée à la racine, autorisée
     **dans** une zone — et écriture dans ce sous-dossier OK (l'autorisation
     de zone **se propage aux sous-dossiers**, sans grant supplémentaire)
   - mise à la corbeille d'un **dossier entier avec son contenu** en un appel
3. **Enseignement de sécurité à consigner.** Le contrôle de zone regarde
   « la cible est-elle sous un dossier autorisé ? », jamais « qui l'a créée ? ».
   Donc accorder une zone = accorder écriture **et** corbeille sur tout son
   contenu, y compris des fichiers que le LLM n'a pas créés. À écrire noir sur
   blanc dans le protocole (et peut-être SECURITY.md).

## Proposition

- Retirer/mettre à jour la section « Limites v1 » (l'upload de contenu est livré).
- Ajouter les phases : suppression définitive (refus attendu), dossiers en zone
  vs hors zone, propagation en sous-dossier, corbeille d'un dossier.
- Consigner l'enseignement « zone = territoire, pas propriété du créateur ».

## Critères d'acceptation

> **Réconciliation (2026-08-08).** En grande partie absorbé : `PROTOCOLE.md` a été
> réécrit par #47 (corbeille = suppression, fiche 0037) et #77 — la section
> « Limites v1 » périmée a disparu, sémantique corbeille + refus hors-zone
> documentés. Reste l'angle **sécurité** non écrit.

- [x] Section « Limites v1 » retirée / à jour (upload de contenu livré) — #47/#77.
- [ ] Consigner « **zone = territoire, pas propriété du créateur** » (accorder une
      zone = écriture + corbeille sur tout son contenu) dans `PROTOCOLE.md`
      (et peut-être `SECURITY.md`).
- [ ] Phase explicite « propagation de l'autorisation aux **sous-dossiers** ».

## Notes

- Découle du run du 2026-07-27. Le fichier `bonjour-20260722-120119-v2.md`
  (run du 22/07, `text/markdown` brut) traîne encore dans le `ZZ-TESTS` de
  `perso` : témoin utile de l'ancien comportement (fichier .md vs Google Doc),
  à laisser ou nettoyer à la main.
