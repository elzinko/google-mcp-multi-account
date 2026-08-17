# Test manuel — `mag grant` résout un dossier par son NOM

Ce test prouve une seule chose, mais à fond : **`mag grant <alias> <dossier>`
accepte un nom de dossier, pas seulement un ID**, et sa résolution est
*correcte, par compte, et sûre*.

« Sûre » veut dire trois choses, toutes vérifiées ici :

1. **Par compte** — le même nom (`ZZ-TESTS`) résout vers un **ID différent**
   dans chaque Drive. Aucune contamination entre profils.
2. **Refus francs** — nom introuvable, nom ambigu (deux dossiers homonymes),
   dossier à la corbeille, nom qui désigne un fichier : chaque cas échoue avec
   un message qui dit quoi faire, et **sans rien accorder**.
3. **Pas de Touch ID gaspillé** — la résolution a lieu **avant** l'élicitation
   signée (bin/mag `cmd_grant`) : un nom invalide ne doit **jamais** faire
   apparaître de dialogue Touch ID.

Référence code : `resolve_folder()` dans `bin/mag` (~ligne 84) et son appel
dans `cmd_grant()` (~ligne 432).

**Rien ne peut casser** : ce test n'écrit **aucun fichier dans Drive**. Il pose
des autorisations temporaires (1 h) et les révoque. Les dossiers de test sont
créés et supprimés par l'humain, dans l'interface Drive.

Prompt de lancement : voir [PROMPT.md](PROMPT.md).

## Prérequis (3 min, humain)

Dans **chaque** Drive concerné (`perso` et `mw`), connecté au bon compte
Google, à la **racine** du Drive :

1. Un dossier **`ZZ-TESTS`** — nom exact, **un seul** exemplaire.
2. Deux dossiers nommés **`ZZ-AMBIGU`** — oui, deux, homonymes. C'est le
   piège du test (Phase 4). À créer dans **un seul** des deux comptes suffit
   (par défaut `perso`), et à supprimer à la fin.
3. Vérifier qu'aucun dossier ne s'appelle **`ZZ-INEXISTANT`** (Phase 4).

*Pourquoi l'humain ?* En mode zones, l'agent ne peut rien créer tant qu'aucune
zone n'est accordée — et accorder une zone est justement ce qu'on teste. Le
bac à sable est donc forcément un geste humain.

Jetons : si un compte n'a pas servi depuis > 7 jours (app OAuth en mode
*Testing*), prévoir `mag add <alias>` en cours de route (erreur `exit code 2`).

## Déroulé (ce que l'agent doit faire)

Conventions : commandes agent via `GWSA_CLIENT=claude-code mag …` (jamais
`gws` nu), tools MCP quand ils existent (`profiles_list`, `drive_list`,
`access_request`). L'agent **ne déverrouille ni n'accorde jamais lui-même**.

### Phase 0 — état des lieux (lecture seule)

- `profiles_list` (MCP) ou `mag list` : confirmer que `perso` et `mw` existent.
- `mag strongauth status` : annoncer si Touch ID sera demandé — cette réponse
  sert de référence pour l'assertion « pas de Touch ID sur un nom invalide ».
- Rappeler les dossiers attendus et demander confirmation qu'ils sont créés.

### Phase 1 — élicitation « unlock » (l'humain déverrouille)

- Tenter `mag perso auth status` → refus « verrouillé 🔒 » **attendu**.
- Demander à l'utilisateur d'exécuter, lui-même :

  ```bash
  mag unlock perso 30
  mag unlock mw 30
  ```

- Re-vérifier `auth status` des deux profils. `exit code 2` → token expiré :
  proposer `mag add <alias>` puis reprendre.

### Phase 2 — cas nominal : le nom résout, par compte

Demander à l'utilisateur d'exécuter, **une commande à la fois** :

```bash
mag grant perso ZZ-TESTS 1
mag grant mw ZZ-TESTS 1
```

L'agent relève ensuite (lecture seule) :

```bash
mag grants perso
mag grants mw
```

Assertions :

- [ ] Chaque sortie de `grant` affiche le **nom résolu** *et* l'**ID** :
      `« perso » : écriture autorisée sous « ZZ-TESTS » (<ID>) pendant 1 h`.
- [ ] Les deux IDs sont **différents** — même nom, deux Drive, deux dossiers.
- [ ] `mag grants <alias>` liste bien la zone, avec son échéance.

### Phase 3 — un ID reste accepté (non-régression)

L'ID est le chemin historique : il doit continuer de marcher, et afficher le
**nom** récupéré depuis Drive (c'est la branche « target ressemble à un ID »
de `resolve_folder`).

Demander :

```bash
mag grant perso <ID_ZZ-TESTS_perso> 1
```

Assertions :

- [ ] Accepté, et le message affiche « ZZ-TESTS » — l'ID a été **renommé** à
      l'affichage, pas recopié brut.
- [ ] `mag grants perso` ne contient **pas** de doublon : re-granter la même
      zone la remplace, elle ne s'empile pas.

### Phase 4 — contrôles négatifs (le cœur du test)

Chaque commande ci-dessous **doit échouer**. Une seule qui passe = test échoué.
**Aucune ne doit déclencher de dialogue Touch ID** : la résolution précède
l'élicitation signée.

Demander à l'utilisateur de les lancer une par une, en signalant à chaque fois
s'il a vu (ou non) un dialogue Touch ID :

```bash
mag grant perso ZZ-INEXISTANT 1     # 1. nom introuvable
mag grant perso ZZ-AMBIGU 1         # 2. deux dossiers homonymes
mag grant mw ZZ-AMBIGU 1            # 3. existe chez perso, pas chez mw
```

Assertions :

- [ ] 1, 2, 3 échouent avec `dossier « … » introuvable ou ambigu — donne son
      ID (fin de l'URL du dossier dans Drive)`.
- [ ] Aucun Touch ID sur ces trois cas.
- [ ] `mag grants perso` / `mag grants mw` sont **inchangés** après ces
      échecs (rien n'a été accordé au passage).
- [ ] Cas 3 en particulier : `ZZ-AMBIGU` existe côté `perso` mais la commande
      sur `mw` échoue — la résolution ne fuit pas d'un compte à l'autre.

Puis deux cas de forme, sans passer par Drive :

```bash
mag grant perso ZZ-TESTS 0          # durée invalide
mag grant perso ZZ-TESTS 999        # durée hors bornes (max 168)
```

- [ ] Les deux échouent : `durée invalide « … » (heures entières, 1 à 168)`.

### Phase 4 bis — le dossier à la corbeille (optionnel, 2 min)

`resolve_folder` filtre `trashed=false`. Pour le prouver :

1. **L'humain** met `ZZ-TESTS` de `mw` à la corbeille depuis Drive.
2. `mag grant mw ZZ-TESTS 1` → doit échouer (« introuvable ou ambigu »).
3. **L'humain** le restaure depuis la corbeille.
4. `mag grant mw ZZ-TESTS 1` → repasse.

- [ ] Un dossier corbeillé est invisible à la résolution ; restauré, il revient.

### Phase 5 — vérification humaine

L'agent donne, pour chaque ID résolu en Phase 2 :

- `https://drive.google.com/drive/folders/<ID>`

L'utilisateur ouvre chaque lien **connecté au bon compte** et confirme que
l'ID pointe bien vers **son** `ZZ-TESTS` — c'est la vérification que la
résolution nom → ID a visé juste, et pas seulement « un » dossier.

L'agent affiche un bilan : cas → commande → attendu → obtenu → ✓/✗.

### Phase 6 — nettoyage (sur accord explicite)

Après le « ok » de l'utilisateur :

```bash
mag grant perso revoke <ID_ZZ-TESTS_perso>
mag grant mw revoke <ID_ZZ-TESTS_mw>
```

*(Ou ne rien faire : les grants posés à 1 h expirent seuls, comme les verrous
à 30 min. Révoquer rend juste le test propre tout de suite.)*

Puis, geste humain dans Drive : supprimer les deux dossiers `ZZ-AMBIGU`.
`ZZ-TESTS` peut rester — il sert aussi au test `drive-2-comptes`.

L'agent ne supprime rien dans Drive : il n'a de toute façon pas le droit de
corbeiller la racine d'une zone (fiche 0037).

## Rejouabilité — le test est idempotent

- Aucun fichier créé dans Drive : rien à recompter d'un run à l'autre.
- Re-granter une zone déjà accordée la **remplace** (Phase 3) : pas d'empilement.
- Verrous et grants expirés entre deux runs : re-demander est normal.
- Seuls les dossiers `ZZ-AMBIGU` sont à recréer avant chaque run (Phase 4).

## Critères de réussite

- [ ] Les profils verrouillés ont refusé toute commande avant unlock.
- [ ] `ZZ-TESTS` résolu par NOM sur les deux comptes, vers **deux IDs distincts**.
- [ ] Un ID brut reste accepté, et son nom est réaffiché.
- [ ] Nom introuvable / ambigu / d'un autre compte : refusés, message utile.
- [ ] Aucun de ces refus n'a déclenché de Touch ID.
- [ ] Les grants n'ont pas bougé après les échecs.
- [ ] (optionnel) Dossier corbeillé : invisible à la résolution ; restauré : revient.
- [ ] Les IDs résolus pointent, à l'œil humain, vers le bon dossier du bon compte.
- [ ] Journal : `scripts/log-usage.py` a tracé les commandes avec `GWSA_CLIENT`.

## Dépannage

| Symptôme | Cause | Remède |
|---|---|---|
| `exit code 2` sur un profil | Token expiré (app en *Testing*, 7 j) | `mag add <alias>` puis reprendre |
| `403 … required permission to use project <id>` | Compte non membre du projet GCP | Rôle `serviceUsageConsumer` — docs/setup-oauth.md §7 |
| `ZZ-TESTS` introuvable alors qu'il existe | Créé dans un sous-dossier, ou dans l'autre compte, ou à la corbeille | Le placer à la **racine** du bon Drive, hors corbeille |
| Touch ID apparaît sur un cas négatif | **Régression** — l'élicitation passerait avant la résolution | Test échoué : ouvrir une fiche backlog |
| `mag grant` accepte `ZZ-AMBIGU` | **Régression** — l'ambiguïté doit être refusée | Vérifier qu'il y a bien 2 dossiers homonymes, sinon fiche |
| L'agent propose de granter lui-même | Interdit (CLAUDE.md) | C'est l'humain qui exécute unlock/grant, toujours |

## Limites connues

- La résolution ne cherche qu'à **plat** (`name='…'`, tout le Drive), pas par
  chemin : deux `ZZ-TESTS` dans des sous-dossiers différents seraient ambigus.
  C'est volontaire — l'ambiguïté est refusée, jamais devinée.
- Une chaîne de 20+ caractères `[A-Za-z0-9_-]` est traitée comme un **ID**, pas
  comme un nom. Un dossier réellement nommé ainsi ne serait pas trouvable par
  nom : donner son ID.
