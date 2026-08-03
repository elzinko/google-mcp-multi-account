# Test E2E — Drive cross-compte (perso ↔ mw)

Protocole **guidé** pour prouver, en une session, les opérations Drive
**entre deux comptes** : création, lecture, **recopie** A→B, **partage**,
**transfert de propriété** (si policy le permet), puis nettoyage réversible.

**Bac à sable** : tout se passe sous `ZZ-TESTS` à la racine de chaque Drive.
Rien d'autre n'est touché (default-deny + zones).

Prompt de lancement : voir [PROMPT.md](PROMPT.md).

## Comptes et rôles

| Alias | Rôle dans le test | Email (vérifier via `gwsa list`) |
|---|---|---|
| `perso` | Compte **source** A | thomas.couderc@gmail.com |
| `mw` | Compte **destination** B | matiereweb@gmail.com |

Inverser A/B en fin de test (phase optionnelle) pour couvrir les deux sens.

## Prérequis (humain, ~5 min)

1. **Dossiers bac à sable** : dans chaque Drive (web, bon compte Google),
   créer **`ZZ-TESTS`** à la racine — nom exact, un seul exemplaire.
   IDs connus (2026-07-29, à re-vérifier via `drive_list`) :
   - **perso** : `1JXzDlNxr-9ZMypNTTc0kK5_EyPrK370Y`
   - **mw** : `1JuH5JubmsEqkjwCinzAWO8eGUT5TIv-Z`
2. **Profils connectés** : `gwsa list` montre `perso` et `mw` connectés.
3. **Partage / transfert** : la policy prudente a `drive.share: false`. Pour
   les phases 6–7, l'humain active le partage **temporairement** via l'admin
   (`http://127.0.0.1:4877`) ou en éditant la policy :
   - cocher **partage** sur le profil **source** (`perso` en premier run)
   - remettre `share: false` après le test si souhaité
4. Jetons : si un compte n'a pas servi depuis > 7 jours, prévoir
   `gwsa add <alias>` (erreur `exit code 2`).

## Tools MCP utilisés

| Tool | Usage |
|---|---|
| `profiles_list` | État des profils |
| `drive_list` | Trouver `ZZ-TESTS`, lister le contenu des zones |
| `drive_get` | Métadonnées + propriétaire (`owner`, `owned_by_me`) |
| `drive_create` | Créer avec contenu (Google Doc depuis markdown) |
| `drive_update` | Modifier nom/contenu en zone |
| `drive_permissions_list` | Lister les partages |
| `drive_permissions_create` | Partager ou transférer la propriété |
| `drive_permissions_delete` | Révoquer un partage de test |
| `access_request` | Élicitation unlock / grant |

Shell de secours (si export binaire nécessaire) :
`GWSA_CLIENT=claude-code gwsa <alias> drive files export …`

## Déroulé

Conventions : MCP de préférence ; shell via `GWSA_CLIENT=claude-code gwsa …`
(jamais `gws` nu). L'agent **ne déverrouille pas** et **n'accorde pas** de zone.

### Phase 0 — état des lieux (lecture seule)

- `profiles_list` : confoncer `perso` et `mw`, noter emails et verrous.
- `drive_list` sur chaque compte avec `query` contenant `name = 'ZZ-TESTS'`
  et `trashed=false` — noter l'**ID** de chaque dossier (ou demander à
  l'humain si ambigu / absent).
- Annoncer le plan : création → copie → partage → transfert (si share actif).

### Phase 1 — élicitation « unlock »

- Tenter une commande sur un profil verrouillé → refus **attendu**.
- Demander à l'humain :

  ```bash
  gwsa unlock perso 30
  gwsa unlock mw 30
  ```

- Re-vérifier. `exit code 2` → `gwsa add <alias>`.

### Phase 2 — élicitation « grant »

- Tenter `drive_create` dans `ZZ-TESTS` **avant** grant → refus zone **attendu**.
- Demander à l'humain :

  ```bash
  gwsa grant perso ZZ-TESTS 2
  gwsa grant mw ZZ-TESTS 2
  ```

- `gwsa grants perso` / `gwsa grants mw` : noter les IDs de zone.

### Phase 3 — création sur le compte source (perso)

Horodatage : `TS=$(date +%Y%m%d-%H%M%S)`.

1. `drive_create` sur **perso** :
   - `parent_id` = ID zone `ZZ-TESTS` de perso
   - `name` = `cross-${TS}.md`
   - `mime_type` = `text/markdown` — **fichier non-natif (blob)**. Un Google Doc
     natif (mime_type par défaut) n'est **pas** modifiable en contenu par
     `drive_update` (revue sécurité F5) ; on crée donc un blob éditable.
   - `content` = markdown distinct, ex. :
     `# Cross-compte perso→mw\n\nCréé le ${TS} depuis **perso**.`
2. Noter `file_id`, `webViewLink`, `owner` — vérifier `owned_by_me: true`.
3. `drive_update` : renommer en `cross-${TS}-v2.md` et **remplacer** le contenu
   (remplacement intégral, pas d'ajout partiel) — vérifier via `drive_get`.

### Phase 4 — recopie cross-compte (perso → mw)

**Modèle produit** : pas de « move » natif entre comptes — on **recopie**
le contenu connu vers le compte B.

1. `drive_create` sur **mw** :
   - `parent_id` = ID zone `ZZ-TESTS` de mw
   - `name` = `copie-depuis-perso-${TS}.md`
   - `content` = **le même texte** que la version finale sur perso (l'agent
     l'a en mémoire depuis la phase 3).
2. `drive_get` sur mw : vérifier `owner` = email mw, `owned_by_me: true`.
3. `drive_list` sur les deux zones : deux fichiers distincts, propriétaires
   différents — preuve de non-contamination.

> **Export depuis un fichier existant** (hors contenu agent) : si le test
> doit copier un binaire ou un Doc dont l'agent n'a pas le texte, l'humain
> ou l'agent via shell exporte d'abord :
> `gwsa perso drive files export --params '{"fileId":"<ID>","mimeType":"text/markdown"}' -o .e2e-tmp/export.md`
> puis `drive_create` / `files create --upload` sur mw.

### Phase 5 — lecture croisée

- Sur **mw** : `drive_get` du fichier copié — lien pour vérification humaine.
- Sur **perso** : `drive_get` de l'original.
- L'humain ouvre chaque `webViewLink` connecté au **bon** compte Google.

### Phase 6 — partage (policy `share: true` requise sur perso)

**Prérequis humain** : activer `drive.share` sur **perso** (admin web).

1. Sans `share:true`, tenter `drive_permissions_create` → refus policy
   **attendu** (enregistrer le message).
2. Après activation par l'humain, **demander confirmation** puis :
   - `drive_permissions_create` sur le fichier **perso** :
     - `email` = email du compte **mw**
     - `role` = `reader`
     - `send_notification` = `false` (si supporté)
3. `drive_permissions_list` sur perso : la permission mw apparaît.
4. L'humain vérifie dans Drive (compte mw) que le fichier partagé est visible.

### Phase 7 — transfert de propriété (hors de cette version)

Le transfert de propriété (`drive_permissions_create transfer_ownership`) a été
**retiré** de cette version et est **refusé** par le serveur : action destructive,
garde de sécurité à concevoir (zones / grant de session / Touch ID) et à valider
sur de vrais comptes @gmail.com (flux `pendingOwner` = invitation à accepter). Il
fait l'objet d'une **PR dédiée, non prête**. → **Skip** cette phase ici.

### Phase 8 — contrôles négatifs

- `drive_permissions_create` sur un profil sans `share:true` → refus.
- Écriture hors zone sur perso → refus.
- Troisième profil resté verrouillé → refus « verrouillé 🔒 ».

### Phase 9 — nettoyage (sur accord explicite)

1. Lister les fichiers créés (liens).
2. `drive_permissions_delete` : révoquer les partages de test (si phase 6).
3. **Corbeille** : sous `delete:false`, l'agent ne peut pas corbeiller —
   l'humain met les fichiers/dossiers de test à la corbeille depuis Drive
   (restaurable 30 jours). Voir [drive-2-comptes](../drive-2-comptes/) phase 6.
4. Remettre `share: false` sur perso si activé pour le test.

## Critères de réussite

- [ ] Refus avant unlock et avant grant (messages d'élicitation utiles).
- [ ] Fichier créé **et modifié** sur perso (`drive_create` + `drive_update`).
- [ ] Copie recréée sur mw avec le bon contenu et le bon propriétaire.
- [ ] Partage reader vers mw visible (`drive_permissions_list` + vérif humaine).
- [ ] Transfert testé **ou** skip documenté avec raison (policy / refus humain).
- [ ] Contrôles négatifs passés.
- [ ] Journal : commandes tracées avec `GWSA_CLIENT`.

## Dépannage

| Symptôme | Cause | Remède |
|---|---|---|
| `partage refusé par la policy` | `share: false` | Admin → cocher partage sur le profil source |
| `dossier « ZZ-TESTS » introuvable` | Pas créé ou corbeille | Recréer/restaurer dans Drive web |
| Fichier copié invisible sur mw | Mauvais `parent_id` ou grant expiré | `gwsa grants mw`, re-granter |
| Transfert échoue | share:false ou fichier dans Shared Drive | Activer share ; tester sur My Drive |
| `owned_by_me: null` | Drive partagé / délai API | Re-lire après quelques secondes |

## Workflow agent — résumé copie / transfert cross-compte

```
perso (zone ZZ-TESTS)                    mw (zone ZZ-TESTS)
─────────────────────                  ────────────────────
drive_create(content=…)  ──recopie──►  drive_create(même content)
       │                                      ▲
       │ partage (share:true)                 │
       └─ drive_permissions_create ───────────┘ (lecture)
       │
       └─ drive_permissions_create            (fichier jetable seulement)
          transfer_ownership=true  ────────► propriétaire = mw
```

Pas de tool « move cross-compte » : recopie + partage + transfert optionnel.
