# Test E2E — Drive sur 2 comptes dans un même prompt

Protocole **guidé et sans risque** pour prouver, en une seule session Claude
Code, que le multi-comptes fonctionne de bout en bout : lecture, élicitation
(unlock + grant), écriture et modification de fichiers dans **2 Drive
différents**, vérification humaine, puis nettoyage réversible.

**Rien ne peut casser** : toute écriture se passe sous un dossier bac à sable
`ZZ-TESTS` créé par l'humain à la racine de chaque Drive, la policy refuse
tout le reste (default-deny, zones), et le nettoyage passe par la
**corbeille** (restaurable 30 jours) — la suppression définitive reste
impossible via gwsa (`emptyTrash` toujours refusé).

Prompt de lancement : voir [PROMPT.md](PROMPT.md).

## Prérequis (2 min, humain)

1. Choisir 2 comptes dans `gwsa list` (ex. `perso` et `zebra`).
2. Dans **chaque** Drive (interface web, connecté au bon compte), créer un
   dossier **`ZZ-TESTS`** à la racine. Nom exact, en un seul exemplaire —
   `gwsa grant` résout le nom en ID et refuse les ambiguïtés.
   *Pourquoi l'humain ?* En mode zones le LLM ne peut écrire nulle part tant
   qu'aucune zone n'est accordée — créer le bac à sable est un geste humain,
   et c'est voulu.
3. Jetons : si un compte n'a pas servi depuis > 7 jours (app OAuth en mode
   *Testing*), prévoir une reconnexion `gwsa add <alias>` en cours de route
   (le protocole le détecte, erreur `exit code 2`).

## Déroulé (ce que l'agent doit faire)

Conventions : toutes les commandes agent passent par
`GWSA_CLIENT=claude-code gwsa …` (jamais `gws` nu), ou par les tools MCP
équivalents quand ils existent (`profiles_list`, `drive_list`, `drive_get`,
`drive_create`, `drive_update`, `drive_permissions_*`, `access_request`).

### Phase 0 — état des lieux (lecture seule)

- `gwsa list` : confirmer que les 2 alias existent et sont 🔒 verrouillés.
- `gwsa strongauth status` : annoncer si Touch ID sera demandé.
- Annoncer le plan et les 2 dossiers `ZZ-TESTS` attendus.

### Phase 1 — élicitation « unlock » (l'humain déverrouille)

- Tenter `gwsa ALIAS1 auth status` → refus « verrouillé 🔒 » **attendu** :
  c'est le test du verrou.
- Demander à l'utilisateur d'exécuter, lui-même (Touch ID si strongauth) :

  ```bash
  gwsa unlock ALIAS1 30
  gwsa unlock ALIAS2 30
  ```

- Re-vérifier `auth status` des 2 profils. `exit code 2` → token expiré :
  proposer `gwsa add <alias>` puis reprendre.

### Phase 2 — élicitation « grant » (l'humain accorde les zones)

- Tenter une écriture **avant** tout grant (ex. `drive files create` avec
  parent `ZZ-TESTS`) → refus de zone **attendu**, avec le message qui dit
  quoi demander : c'est le test du default-deny vivant.
- Demander à l'utilisateur :

  ```bash
  gwsa grant ALIAS1 ZZ-TESTS 2
  gwsa grant ALIAS2 ZZ-TESTS 2
  ```

- `gwsa grants ALIAS1` / `ALIAS2` : noter l'ID de zone de chaque compte.
  (Les grants expirent en 2 h — c'est normal, c'est le produit.)

### Phase 3 — écriture croisée (le cœur du test)

**Pré-vol** : lister le contenu de chaque zone (`drive files list` avec
`'<ID_ZONE>' in parents and trashed=false`). S'il reste des fichiers d'un
run précédent, le signaler et proposer de les mettre à la corbeille (possible
seulement si la zone accorde `delete:true` — fiche 0037) — ou de les ignorer :
les noms horodatés garantissent qu'ils ne gênent pas.

Pour **chaque** compte, dans la même session :

1. Écrire localement (scratchpad) un fichier `bonjour-<date>.md` au contenu
   **distinct** : « Bonjour depuis ALIAS (email) — créé le <horodatage> ».
2. Le créer **avec contenu** dans la zone :

   ```bash
   gwsa ALIAS1 drive files create \
     --json '{"name":"bonjour-<date>.md","parents":["<ID_ZONE_1>"]}' \
     --upload <fichier-local> --upload-content-type text/markdown
   ```

3. Le **modifier** (contenu + renommage en un appel) :

   ```bash
   gwsa ALIAS1 drive files update --params '{"fileId":"<ID_FICHIER>"}' \
     --json '{"name":"bonjour-<date>-v2.md"}' \
     --upload <fichier-local-v2> --upload-content-type text/markdown
   ```

   ⚠️ `fileId` dans `--params`, parents dans `--json` — c'est ce que le
   contrôleur vérifie. Le raccourci `drive +upload` est volontairement
   **bloqué** en mode zones (non vérifiable) : utiliser `files create/update`.

   ⚠️ garde-fou gws : le fichier passé à `--upload` doit être **sous le
   répertoire courant** (sinon `validationError … outside the current
   directory`). Écrire les fichiers temporaires dans le repo (ex.
   `.e2e-tmp/`, supprimé en fin de phase), pas dans un scratchpad externe.

Même nom de fichier dans les deux comptes, contenus différents : la
non-contamination entre profils devient vérifiable à l'œil nu.

### Phase 4 — contrôles négatifs (prouver que les barrières tiennent)

- Écriture **hors zone** sur ALIAS1 (parent inventé ou absent) → refus.
- Une commande sur un **3ᵉ profil resté verrouillé** → refus « verrouillé 🔒 ».
- Ces deux refus doivent apparaître dans le bilan comme des ✓.

### Phase 5 — vérification humaine

L'agent donne, pour chaque compte :

- l'URL du dossier : `https://drive.google.com/drive/folders/<ID_ZONE>`
- le `webViewLink` de chaque fichier (`drive_get` / `drive files get`)

L'utilisateur ouvre chaque lien **connecté au bon compte Google** et confirme :
bon fichier, bon contenu, bon compte. L'agent recoupe de son côté
(`drive_list` sur chaque zone) et affiche un bilan : compte → actions →
résultat.

### Phase 6 — nettoyage (sur accord explicite, réversible)

Depuis la **fiche 0037**, la racine d'une zone est une **frontière immuable** :
le LLM ne peut pas la corbeiller (ni la renommer / déplacer), et mettre à la
corbeille exige `delete:true` (corbeille = suppression). Avec le préréglage
prudent (`delete:false`), **le nettoyage des dossiers de zone est un geste
humain**. Donc, après le « ok » de l'utilisateur :

1. L'agent **liste** ce qu'il a créé (liens) et annonce qu'il **ne peut pas**
   corbeiller les dossiers `<ID_ZONE_1>` / `<ID_ZONE_2>` — c'est voulu.
2. **L'humain** met ces dossiers à la corbeille depuis Drive (restaurable
   30 jours), ou les garde pour un futur run.

Les commandes `files update {"trashed":true}` sur `<ID_ZONE_n>` **échouent
désormais** (exit 4) : ne pas les proposer. Alternative : garder les dossiers —
les grants expirent tout seuls, verrous et grants se referment automatiquement
(30 min / 2 h). Vider la corbeille reste un geste 100 % humain, dans Drive.

## Rejouabilité — le test est idempotent

- **Noms horodatés** (`bonjour-<TS>.md`) : deux runs ne se marchent jamais
  dessus ; le recomptage ne considère que les fichiers du run courant.
- **Restes d'un run précédent** : signalés au pré-vol de la Phase 3,
  corbeille proposée (jamais imposée).
- **Dossier `ZZ-TESTS` parti à la corbeille** lors d'un nettoyage précédent :
  le restaurer ou le recréer avant de re-granter — `gwsa grant` ne résout que
  les dossiers non corbeille (`trashed=false`).
- **Verrous et grants expirés** entre deux runs : re-demander est normal,
  c'est le produit.
- **Fichiers locaux** : `.e2e-tmp/` (gitignoré), supprimé en fin de Phase 3.

## Critères de réussite

- [ ] Les 2 profils verrouillés ont refusé toute commande avant unlock.
- [ ] L'écriture a été refusée avant grant, avec un message d'élicitation utile.
- [ ] Un fichier créé **et modifié** (contenu + nom) dans chaque compte.
- [ ] Contenus distincts vérifiés dans les 2 Drive (liens fournis, bon compte).
- [ ] Écriture hors zone refusée ; 3ᵉ profil resté inaccessible.
- [ ] Nettoyage : l'agent ne corbeille pas la racine de zone (refus attendu,
      fiche 0037) ; dossiers mis à la corbeille par l'humain (ou conservés).
- [ ] Journal : `scripts/log-usage.py` a tracé les commandes avec
      `GWSA_CLIENT` (visible dans l'admin, section journal).

## Dépannage

| Symptôme | Cause | Remède |
|---|---|---|
| `exit code 2` sur un profil | Token expiré (app en *Testing*, 7 j) | `gwsa add <alias>` puis reprendre |
| `403 … required permission to use project <id>` | Le compte n'est pas membre du projet GCP de l'app OAuth (quota project) | Rôle `serviceUsageConsumer` à accorder — voir docs/setup-oauth.md §7 |
| `dossier « ZZ-TESTS » introuvable ou ambigu` | Pas créé, mal orthographié, ou deux dossiers du même nom | Créer/renommer dans Drive web, ou donner l'ID (fin de l'URL du dossier) |
| Refus « non vérifiable par zones » sur `+upload` | Comportement voulu | `files create/update` + `--upload` |
| `validationError … outside the current directory` sur `--upload` | Garde-fou gws : chemin hors du répertoire courant | Fichier temporaire sous le repo (ex. `.e2e-tmp/`), supprimé après |
| Refus de zone alors que le grant vient d'être posé | Grant expiré ou zone d'un autre compte | `gwsa grants <alias>`, re-granter |
| L'agent propose de déverrouiller lui-même | Interdit (CLAUDE.md) | C'est l'humain qui exécute unlock/grant, toujours |

## Limites connues (mises à jour 2026-07)

- `drive_update` et `drive_permissions_*` sont exposés en MCP ; les phases 3
  peuvent les utiliser à la place de `gwsa … files update --upload`.
- **Corbeille = suppression (fiche 0037)** : nettoyage des dossiers de zone =
  geste humain (Phase 6). Voir aussi [drive-cross-compte](../drive-cross-compte/)
  pour partage / transfert entre comptes.
- Copie cross-compte : pas de move natif — recopie via `drive_create` ou
  export shell + upload (protocole dédié drive-cross-compte).
