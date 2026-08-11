---
name: gws-multi-account
description: "Piloter plusieurs comptes Google (Gmail, Drive, Calendar, Docs, Sheets, Tasks) via le wrapper gma. Utiliser dès qu'une tâche vise un compte Google précis ou plusieurs comptes : lire/envoyer des mails, gérer des fichiers Drive, consulter des agendas."
---

# Multi-comptes Google avec gma / MCP

Chaque compte Google est un **profil** nommé (alias). Le serveur MCP
(`bin/google-mcp` → `gateway/`) est le chemin **recommandé** pour Gmail/Drive.
Le wrapper `gma` reste pour l'admin et les skills shell.

## Workflow

1. Tool MCP `profiles_list` — ou `gma list` — voir les profils.
2. Choisir l'alias ; si verrouillé → `access_request` kind=unlock (humain).
3. Données : tools `gmail_*` / `drive_*`. Shell de secours :
   `gma <alias> <service> …` (jamais `gws` nu).

## Écrire sur Drive : élicitation obligatoire

Par défaut, aucune zone d'écriture Drive. Avant d'écrire :
1. Vérifier grants / policy ; si refus → tool `access_request` kind=grant.
2. Attendre que l'utilisateur exécute `gma grant …` (ou admin).
3. Les grants expirent : redemander à chaque session est NORMAL.

## Copie / partage cross-compte

Pas de « move » natif entre comptes Google. Workflow MCP :

1. **Recopie** (recommandé) : `drive_get` sur A (métadonnées) puis `drive_create`
   sur B dans sa zone `ZZ-TESTS` avec le même `content` (texte/markdown).
2. **Partage** : `drive_permissions_create` sur A (`email` = compte B,
   `role` = reader|writer) — nécessite `drive.share: true` dans la policy
   (l'humain active via admin ou `gma policy`).
3. **Transfert de propriété** : **indisponible dans cette version** —
   `drive_permissions_create` refuse `transfer_ownership` (fonction déplacée dans
   une PR dédiée, non prête).

Test d'intégration guidé : `tests/manuels/drive-cross-compte/` (perso ↔ mw).

Binaire ou export d'un Doc existant : shell `gma <alias> drive files export …`
puis upload sur B (`files create --upload` ou `drive_create` si texte).

## Pièges

- `gws` nu ou `GOOGLE_WORKSPACE_CLI_CONFIG_DIR=…` = contourne policy/verrou : interdit.
- Toujours s'identifier : MCP le fait (`GWSA_CLIENT=mcp`) ; en shell `GWSA_CLIENT=claude-code`.
- Exit code 2 = token expiré → `gma add <alias>`.
- Profil verrouillé = demander unlock humain — jamais contourner.
- Pas d'envoi mail via MCP (brouillons seulement).
- Doc : `docs/mcp-setup.md`, `docs/threat-model.md`.
