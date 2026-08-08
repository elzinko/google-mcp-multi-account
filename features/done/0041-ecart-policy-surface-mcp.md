---
id: 0041
title: Clarifier l'écart policy admin ↔ surface MCP (Drive copie, contenu, modification)
type: bug
priority: P2
version:
epic:
status: shipped
ready: 2026-07-28
pr: "#52"
created: 2026-07-28
---

## Contexte / Problème

L'interface admin Policy coche **lecture / création / modification** (Drive) et
affiche Calendar / Keep dans les services du profil. Un utilisateur (ou un LLM)
en déduit à tort qu'il peut **copier-coller un fichier Drive** : « lecture +
création (+ modification) = copie ».

Or deux couches distinctes se superposent :

| Couche | Rôle | Drive aujourd'hui |
|---|---|---|
| **Policy** (`gwsa policy` / admin) | Ce que `gws` a le droit d'appeler (fail closed) | `files get/list/export/download` ; `create`/`copy` si création ; `update` si modification ; zones |
| **Tools MCP** (`google-mcp`) | Ce que le LLM peut réellement invoquer | `drive_list`, `drive_get` (**métadonnées seules**), `drive_create` (fichier neuf + contenu texte optionnel) |

Conséquences concrètes :

1. **Pas de copie via MCP** — pas de tool `drive_copy`. La policy classe pourtant
   `files.copy` comme *création* (donc autorisé si la case est cochée + zone),
   mais seul `gwsa … drive files copy` y a accès, pas le serveur MCP.
2. **Pas d'approximation « lire puis recréer »** — `drive_get` appelle
   `files.get` sans export/download : le corps du fichier n'est jamais exposé.
   `drive_create(content=…)` ne sert que si le LLM *invente* ou *possède déjà*
   le texte.
3. **« Modification » cochée ≠ tool MCP** — aucun `drive_update` ; la case
   n'autorise que la CLI.
4. **Calendar / Keep dans la policy** sans tool MCP correspondant (déjà noté
   dans la fiche [[0021]] pour l'élargissement).

Constaté en session 2026-07-28 : question « ai-je le droit de copier-coller des
fichiers avec mw ? » — réponse correcte « non via MCP », mais la UI Policy
donnait l'impression inverse.

## Proposition

Deux volets, livrables séparément :

### A — Clarifier (cette PR)

Rendre l'écart **visible** là où l'humain configure et lit :

- Note dans le dialogue Policy admin : les cases = droits `gwsa` / API ; la
  surface MCP est un **sous-ensemble** (lien ou rappel des tools Drive
  existants).
- Précision dans `docs/mcp-setup.md` : `drive_get` = métadonnées ; pas de
  copie / pas de modification d'existant / pas d'export de contenu via MCP.
- Cette fiche backlog pour ne pas perdre le sujet capacité.

### B — Capacités Drive manquantes (suite, hors scope immédiat)

Si on veut que le LLM puisse vraiment « copier » sous policy + zones :

- Tool MCP `drive_copy` → `files.copy` (catégorie policy `create`, parent en
  zone) — vraie copie Drive (binaire, Doc, permissions de base).
- Optionnel : `drive_export` / lecture de contenu (texte) pour les cas où
  « lire puis recréer » est voulu — distinct de la copie native.
- Optionnel plus tard : `drive_update` aligné sur la case modification.

Rester fail closed et zoné comme `drive_create`. Voir aussi [[0021]] pour
Calendar / Docs / Sheets / Tasks.

## Critères d'acceptation

- [x] Fiche backlog qui décrit l'écart policy ↔ MCP et le cas « copie Drive ».
- [x] Dialog Policy admin : note explicite que les cases n'égalent pas les
      tools MCP (sous-ensemble Drive actuel rappelé).
- [x] `docs/mcp-setup.md` : `drive_get` = métadonnées ; absence de copie /
      update / export de contenu côté MCP.
- [x] (Suite) Tool `drive_copy` + tests hermétiques, si on décide d'ouvrir la
      capacité — fait via la fiche [[0043]] (avec `drive_read` et
      `drive_upload`).

## Notes

- `scripts/policy-check.py` : `copy` ∈ catégorie `create` (l. 246–247).
- Surface MCP listée dans `gateway/mcp_server.py` / `docs/mcp-setup.md`.
- Ne pas confondre avec [[0038]] (création de *dossier-zone* par l'humain) ni
  [[0024]] (contenu au *create*, déjà livré).
