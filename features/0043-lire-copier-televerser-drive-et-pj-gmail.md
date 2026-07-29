---
id: 0043
title: Lire, copier, téléverser — contenu Drive et pièces jointes Gmail via MCP
type: feature
priority: P1
version:
epic:
status: in-progress
ready: 2026-07-29
pr:
created: 2026-07-29
---

## Contexte / Problème

Quatre manques constatés en usage réel (session devis Paroi-Services,
2026-07-29). Le serveur MCP sait désormais déposer un Google Doc rédigé
(fiche [[0024]]) mais reste aveugle et manchot autour de ce dépôt :

1. **Pas de lecture de contenu** (`drive_get` = métadonnées seules).
   Impossible de relire un document déposé pour le vérifier, ou de lire un
   modèle existant avant de s'en inspirer. Manque n° 1 constaté.
2. **Pas de téléversement binaire.** Un devis PDF généré localement n'a pas
   pu être déposé : `drive_create` n'accepte que du texte à convertir.
3. **Pas de copie native.** Dupliquer un modèle de devis (Google Sheet) vers
   le dossier client est impossible — « lire puis recréer » ne préserve ni le
   type ni la mise en forme.
4. **Pas d'accès aux pièces jointes Gmail.** Logo et catalogue envoyés en PJ
   par un client, non récupérables.

C'est le volet B de la fiche [[0041]] (écart policy ↔ surface MCP), étendu à
l'upload et aux pièces jointes. La policy classe déjà correctement ces
méthodes (`export`/`download` = lecture ; `copy`/`upload` = création zonée) :
seule la surface MCP manquait.

Vérifié au préalable : le bug `gmail_draft_create` (« Required path parameter
userId is missing ») revu en prod est déjà corrigé dans la source (fiche
[[0024]], `--params {"userId":"me"}`) — le build déployé était simplement en
retard. Remède : redéployer (`./scripts/update.sh`), pas de code.

## Proposition

Quatre tools, mêmes gardes que l'existant (verrou de profil via `_run`,
policy default-deny côté broker, zones côté destination) :

- **`drive_read`** — lecture du contenu en texte. Fichier Google : `files
  export` (markdown par défaut pour un Doc, CSV pour un Sheet, format
  explicite possible parmi les formats texte de la fiche 0024). Fichier
  ordinaire textuel : `files get alt=media`. Binaire : refus explicite.
  Contenu tronqué à `max_chars` (défaut 100 000) avec indicateur `truncated`.
- **`drive_copy`** — copie native `files.copy` vers un dossier de zone :
  `fileId` en `--params`, `parents` (destination) en `--json` — le seul
  endroit que `policy-check.py` lit pour vérifier la zone.
- **`drive_upload`** — téléversement d'un fichier local (binaire compris)
  via le répertoire de dépôt du broker (ADR-0003), sans conversion. Jamais
  de lecture sous `GWSA_ROOT` (tokens/credentials), à l'exception de
  `.downloads` (re-téléverser une PJ reçue). Taille plafonnée (50 Mo).
- **`gmail_attachment_get`** — `messages.attachments.get`, contenu décodé
  (base64url) écrit dans `<GWSA_ROOT>/.downloads` : destination JAMAIS
  choisie par l'appelant, nom assaini, jamais d'écrasement (ADR-0006).
  Renvoie chemin, taille et sha256.

Hors périmètre, par design : suppression, transfert de propriété,
`drive_update` (gestes humains ou fiche ultérieure).

## Critères d'acceptation

- [ ] `drive_read` relit un Google Doc déposé (markdown) et un Sheet (CSV) ;
      un binaire est refusé avec un message clair ; troncature signalée.
- [ ] `drive_copy` copie vers une zone autorisée et il est refusé hors zone /
      sans parent (policy `files copy` = création zonée).
- [ ] `drive_upload` dépose un PDF tel quel (multipart, pas de conversion),
      le média transite par le dépôt broker et est effacé même en cas
      d'échec ; refus : fichier absent, trop gros, ou sous `GWSA_ROOT`.
- [ ] `gmail_attachment_get` écrit la PJ décodée dans `.downloads` (0600,
      nom assaini et unique), jamais ailleurs, et renvoie le chemin.
- [ ] Les quatre tools refusent sous verrou de profil, refus journalisé
      (`usage.jsonl`, reason `locked`).
- [ ] Aucun appel gws n'omet un paramètre de chemin (famille du bug 0024).
- [ ] `.downloads` n'apparaît jamais comme un profil.
- [ ] `./scripts/test.sh` vert (hermétique, sans compte réel ni `gws`).

## Notes

- ADR-0003 (contenu via dépôt broker) réutilisé pour l'upload ;
  [ADR-0006](../docs/adr/ADR-0006-fichiers-recus-repertoire-dedie.md) pour
  le sens descendant (fichiers reçus).
- Clôt le volet B de [[0041]] ; élargissement à d'autres services : [[0021]].
- `attachment_id` se trouve dans `gmail_get` → `payload.parts[].body.attachmentId`.
