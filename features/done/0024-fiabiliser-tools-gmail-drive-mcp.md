---
id: 0024
title: Fiabiliser les tools Gmail/Drive du MCP — brouillon cassé, Drive sans contenu ni propriétaire
type: bug
priority: P1
version:
epic:
status: shipped
ready: 2026-07-26
pr: "#26"
created: 2026-07-26
---

## Contexte / Problème

Trois défauts constatés à l'usage réel du serveur MCP, tous dans
`gateway/api.py`. Ils se cumulent pour rendre le dépôt d'un livrable
impossible sur le bon compte.

**1. `gmail_draft_create` est cassé (bug).** L'appel renvoie systématiquement :

```
gws a échoué : error[validation]: Required path parameter userId is missing.
Provide it via --params
```

La commande ne passe que `--json` (le corps) et jamais le paramètre de chemin
`userId`. `gws schema gmail.users.drafts.create` confirme le contrat :
`path = gmail/v1/users/{userId}/drafts`. `gmail_get` et `gmail_list`, eux,
passent bien `{"userId": "me"}` via `--params` : le brouillon est le seul
appel du fichier à avoir oublié son paramètre de chemin.

**2. `drive_create` ne sait créer que des fichiers vides (manque).** Elle ne
pose que les métadonnées (`name`, `mimeType`, `parents`). Impossible de
déposer un document rédigé : l'agent crée une coquille vide et n'a aucun
moyen d'y écrire le texte. Blocant à l'usage — l'autre connecteur Drive
disponible sait écrire du contenu mais est authentifié sur le **mauvais
compte**, donc tout ce qu'il crée atterrit chez le mauvais propriétaire.
C'est exactement le problème que ce projet existe pour résoudre.

**3. `drive_get` / `drive_list` ne remontent pas le propriétaire (manque).**
Le champ `fields` ne demande ni `owners` ni `ownedByMe`. Or vérifier qu'un
livrable client appartient bien au bon compte est une règle du projet
utilisateur : sans cette information, la vérification est impossible sans
ouvrir le navigateur.

## Proposition

1. Ajouter `--params {"userId": "me"}` à `gmail users drafts create`, et
   vérifier le même oubli sur tous les autres appels gmail/drive du fichier.
2. Ajouter un paramètre de contenu optionnel à `drive_create` (et au tool MCP
   `drive_create`) : le texte est déposé en **upload multipart** via
   `gws … --upload <fichier> --upload-content-type <mime>`, et Drive convertit
   la source (markdown ou texte brut) vers `application/vnd.google-apps.document`.
   Le transport du contenu jusqu'à gws fait l'objet de l'**ADR-0003** (gws
   refuse tout `--upload` hors de son répertoire courant).
3. Ajouter `owners(emailAddress)` et `ownedByMe` aux `fields` de `drive_get`,
   `drive_list` (et `drive_create`, pour vérifier le dépôt au moment où il se
   fait), et exposer le propriétaire dans le résultat du tool.

## Critères d'acceptation

- [ ] `gmail_draft_create` construit `--params {"userId":"me"}` **et** `--json`
      — plus d'`error[validation]` sur `userId`.
- [ ] Aucun appel gmail/drive de `gateway/api.py` n'omet un paramètre de
      chemin de son schéma gws (test qui parcourt les appels construits).
- [ ] `drive_create(..., content="…")` produit un Google Doc **rédigé** :
      `--upload` pointe un fichier qui contient exactement le texte, avec le
      bon `--upload-content-type` ; sans `content`, le comportement actuel est
      inchangé (aucun `--upload`).
- [ ] Le fichier déposé vit dans le répertoire de dépôt du broker (= le cwd de
      gws) et est effacé après l'appel, y compris en cas d'échec.
- [ ] `content_type` hors des formats texte supportés → refus explicite.
- [ ] `drive_get` renvoie `owner` + `owned_by_me` ; `drive_list` renvoie une
      entrée `ownership` par fichier ; les deux demandent bien
      `owners(emailAddress)` et `ownedByMe` dans `fields`.
- [ ] Les zones Drive restent appliquées : `parents` reste dans `--json`, seul
      endroit que `scripts/policy-check.py` lit pour vérifier la zone.
- [ ] `./scripts/test.sh` vert (tests hermétiques, sans compte réel ni `gws`).

## Notes

- Grammaire gws vérifiée en `--dry-run` (validation locale, aucun appel API) :
  `gws drive files create --json … --upload ./doc.md --upload-content-type
  text/markdown --dry-run` → `is_multipart_upload: true`, URL
  `https://www.googleapis.com/upload/drive/v3/files`.
- gws refuse un `--upload` dont le chemin résolu sort de son répertoire
  courant (`… resolves to … which is outside the current directory`) → ADR-0003.
- La macro `gws drive +upload` n'est pas utilisable ici : `policy-check.py`
  refuse les macros `+…` en mode `zonesOnly` (destination non vérifiable).
