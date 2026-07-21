---
name: gws-multi-account
description: "Piloter plusieurs comptes Google (Gmail, Drive, Calendar, Docs, Sheets, Tasks) via le wrapper gwsa. Utiliser dès qu'une tâche vise un compte Google précis ou plusieurs comptes : lire/envoyer des mails, gérer des fichiers Drive, consulter des agendas."
---

# Multi-comptes Google avec gwsa / MCP

Chaque compte Google est un **profil** nommé (alias). Le serveur MCP
(`bin/google-mcp` → `gateway/`) est le chemin **recommandé** pour Gmail/Drive.
Le wrapper `gwsa` reste pour l'admin et les skills shell.

## Workflow

1. Tool MCP `profiles_list` — ou `gwsa list` — voir les profils.
2. Choisir l'alias ; si verrouillé → `access_request` kind=unlock (humain).
3. Données : tools `gmail_*` / `drive_*`. Shell de secours :
   `gwsa <alias> <service> …` (jamais `gws` nu).

## Écrire sur Drive : élicitation obligatoire

Par défaut, aucune zone d'écriture Drive. Avant d'écrire :
1. Vérifier grants / policy ; si refus → tool `access_request` kind=grant.
2. Attendre que l'utilisateur exécute `gwsa grant …` (ou admin).
3. Les grants expirent : redemander à chaque session est NORMAL.

## Pièges

- `gws` nu ou `GOOGLE_WORKSPACE_CLI_CONFIG_DIR=…` = contourne policy/verrou : interdit.
- Toujours s'identifier : MCP le fait (`GWSA_CLIENT=mcp`) ; en shell `GWSA_CLIENT=claude-code`.
- Exit code 2 = token expiré → `gwsa add <alias>`.
- Profil verrouillé = demander unlock humain — jamais contourner.
- Pas d'envoi mail via MCP (brouillons seulement).
- Doc : `docs/mcp-setup.md`, `docs/threat-model.md`.
