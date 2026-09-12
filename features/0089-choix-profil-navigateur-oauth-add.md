---
id: 0089
title: Choisir le profil navigateur (Chrome/…) à l'ouverture OAuth de `mag add`
type: feature
priority: P2
version:
epic:
status: todo
ready:
pr:
created: 2026-08-29
---

## Contexte / Problème

Connecter un compte (`mag add <alias> <email>`) délègue le login OAuth à
`gws auth login`, qui **ouvre le navigateur par défaut du système** — sans aucun
contrôle du profil. Quand l'utilisateur a **plusieurs profils Chrome** (un par
compte Google), l'onglet Google s'ouvre dans le profil actif, au hasard. Si le bon
compte n'y est pas déjà connecté, il faut se ré-authentifier à la main (mots de passe
pas toujours mémorisés). Le bon profil, lui, est déjà authentifié → connexion en un clic.

Constaté en test manuel (2026-08-29, connexion de `lesdoublez@gmail.com` depuis
l'admin) : l'onglet s'ouvre dans un profil arbitraire ; l'utilisateur a « eu de la
chance » que le compte cible soit déjà ouvert.

## Proposition (à groomer)

> ⚠️ **Faisabilité à prouver par un spike AVANT tout dev.** Tout le mécanisme dépend de
> **récupérer l'URL OAuth** pour l'ouvrir soi-même dans le bon profil. Or `gws auth login`
> **ouvre le navigateur par défaut lui-même et n'expose pas l'URL** (vérifié : seules
> options `--readonly/--full/--scopes/--services`, aucune variable d'env hors
> `GOOGLE_WORKSPACE_CLI_CONFIG_DIR`). **Étape 0 = un spike qui tranche : peut-on obtenir
> l'URL ? Sinon la fiche se réduit au repli « afficher l'URL à coller ».**

Offrir, au moment de `mag add` (CLI **et** écran admin « Connecter un compte »), un choix :

- **sans profil** — comportement actuel : navigateur par défaut ;
- **avec profil** — ouvrir l'URL OAuth dans un profil navigateur nommé.

### Commandes par OS (piste technique)

Ouvrir une URL dans un profil Chrome donné dépend de l'OS :

- **macOS**

  ```bash
  open -na "Google Chrome" --args --profile-directory="Profile 1" "<url>"
  ```

- **Linux**

  ```bash
  google-chrome --profile-directory="Profile 1" "<url>"
  # variantes : chromium --profile-directory="…"  |  microsoft-edge --profile-directory="…"
  ```

- **Windows** (cmd / PowerShell)

  ```bat
  "C:\Program Files\Google\Chrome\Application\chrome.exe" --profile-directory="Profile 1" "<url>"
  ```

Le nom de profil (`Default`, `Profile 1`, `Profile 2`…) est le **répertoire** interne du
navigateur, pas le libellé affiché. Correspondance lisible → répertoire dans le fichier
`Local State` du navigateur :

- macOS : `~/Library/Application Support/Google/Chrome/Local State`
- Linux : `~/.config/google-chrome/Local State`
- Windows : `%LOCALAPPDATA%\Google\Chrome\User Data\Local State`

### Obtenir l'URL (le point dur)

- `gws auth login` accepte-t-il un mode « n'ouvre pas, imprime l'URL » ? À vérifier /
  demander en amont (c'est l'objet du spike).
- Sinon, repli honnête : **afficher l'URL à coller** manuellement dans le bon profil.
- « Pré-ouvrir le bon profil » ne suffit **pas** : `gws` ouvrira quand même dans le
  navigateur *par défaut* — écarté, sauf à piloter le navigateur par défaut du système.

## Critères d'acceptation (à affiner au grooming)

- **Given** plusieurs profils Chrome **When** `mag add <alias> <email> --profile "<nom>"`
  **Then** l'onglet OAuth s'ouvre dans ce profil (si le spike a prouvé l'accès à l'URL).
- **Given** aucun profil demandé **Then** comportement actuel inchangé (navigateur défaut).
- L'admin « Connecter un compte » propose le même choix (liste des profils détectés).
- **Test** : la **construction de la commande** par OS est couverte par un test
  table-driven (fonction pure `OS + profil → argv`), **sans lancer de navigateur**. Pas
  de test « vrai navigateur » : la gate du repo est shell + `act`/Docker (Linux), macOS
  sur l'hôte, Windows non couvert.

## Notes

- **Confort, pas sécurité.** Le filet « MAUVAIS COMPTE » (`cmd_add`, exit 4) reste la
  garantie que seul l'email attendu est accepté, quel que soit le profil ouvert.
- Idée issue d'une session de test manuel (connexion multi-profils Chrome).
