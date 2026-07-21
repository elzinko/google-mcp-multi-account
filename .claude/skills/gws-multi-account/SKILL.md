---
name: gws-multi-account
description: "Piloter plusieurs comptes Google (Gmail, Drive, Calendar, Docs, Sheets, Tasks) via le wrapper gwsa. Utiliser dès qu'une tâche vise un compte Google précis ou plusieurs comptes : lire/envoyer des mails, gérer des fichiers Drive, consulter des agendas."
---

# Multi-comptes Google avec gwsa

Chaque compte Google est un **profil** nommé (alias). Le wrapper `gwsa`
(`bin/gwsa`, aussi dans le PATH) route chaque commande `gws` vers le bon compte
en positionnant `GOOGLE_WORKSPACE_CLI_CONFIG_DIR=~/.config/gws-accounts/<alias>`.

## Workflow

1. `gwsa list` — voir les profils disponibles et leur email.
2. Choisir l'alias correspondant à la demande (demander à l'utilisateur si ambigu).
3. Exécuter : `gwsa <alias> <service> <resource> <method> [flags]` — même syntaxe
   que `gws`, documentée dans les skills `gws-gmail`, `gws-drive`, `gws-calendar`, etc.
   (y remplacer `gws` par `gwsa <alias>`).

## Exemples

```bash
gwsa perso gmail users messages list --params '{"userId":"me","maxResults":10,"q":"is:unread"}'
gwsa assoc drive files list --params '{"pageSize":20,"q":"trashed=false"}'
gwsa perso calendar events list --params '{"calendarId":"primary","maxResults":10}'
gwsa perso calendar +agenda --today
```

## Écrire sur Drive : élicitation obligatoire

Par défaut, aucune zone d'écriture Drive. Avant d'écrire :
1. `gwsa grants <alias>` — zones temporaires actives ; `gwsa policy <alias> show` — zones permanentes.
2. Cible hors zones → refus « policy drive ». Ne pas contourner : proposer à
   l'utilisateur la commande exacte et attendre son accord explicite :
   `gwsa grant <alias> "<NomDossier>" [heures]` (temporaire, expire seul — recommandé).
3. Les grants expirent : redemander à chaque session de travail est NORMAL.

## Pièges

- `gws` nu = profil par défaut hors projet : ne pas l'utiliser ici.
- Toujours s'identifier : `GWSA_CLIENT=claude-code gwsa …` (journal d'audit).
- Exit code 2 = token expiré → reconnecter avec `gwsa add <alias>`.
- Profil verrouillé 🔒 (exit 3) = accès sur demande : demander à l'utilisateur
  de lancer `gwsa unlock <alias> [minutes]` — jamais le faire de sa propre initiative.
- Toute action visible de l'extérieur (envoi, partage, invitation) : confirmer
  d'abord le compte et le contenu avec l'utilisateur.
- Comparer/agréger plusieurs comptes = boucler sur les alias :
  `for a in perso assoc; do gwsa "$a" calendar +agenda --today; done`
