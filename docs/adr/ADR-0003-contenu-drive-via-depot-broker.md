# ADR-0003 : Le contenu d'un fichier Drive transite par le répertoire de dépôt du broker

**Statut :** Accepté
**Date :** 2026-07-26
**Décideurs :** Thomas (PO)

## Contexte

`drive_create` ne savait poser que des métadonnées (`name`, `mimeType`,
`parents`) : elle créait des fichiers **vides** (fiche 0024). Or l'usage réel
est « déposer un livrable rédigé dans le Drive du bon compte » — c'est la
raison d'être du projet, les autres connecteurs Drive écrivant du contenu mais
sur le mauvais compte.

L'API Drive attend un **upload multipart** (métadonnées + média dans la même
requête) ; c'est aussi ce qui déclenche la conversion `text/markdown` ou
`text/plain` → `application/vnd.google-apps.document`. Côté CLI, cela s'écrit :

```
gws drive files create --json '{…}' --upload <fichier> --upload-content-type text/markdown
```

Deux contraintes cadrent la solution :

1. **gws n'accepte pas de contenu en mémoire** — seulement `--upload <chemin>`.
   Il faut donc matérialiser le texte dans un fichier.
2. **gws refuse tout chemin résolu hors de son répertoire courant** :
   `--upload '/tmp/x.md' resolves to '/private/tmp/x.md' which is outside the
   current directory`. Un `tempfile` classique dans `/tmp` est donc inutilisable :
   le cwd de gws, c'est celui du **broker**, qui dépend de la façon dont il a
   été démarré (`REPO_DIR` en démarrage automatique, quelconque à la main).

S'ajoute la doctrine du projet (ADR-0002) : le broker est le seul process qui
exécute gws ; la gateway ne lance aucun subprocess gws.

## Décision

**Créer un répertoire de dépôt dédié, `<GWSA_ROOT>/.uploads` (0700), et faire
exécuter gws par le broker avec ce répertoire comme répertoire courant.**

- La gateway y écrit le contenu dans un fichier temporaire (0600, créé par
  `mkstemp`), passe son chemin en `--upload`, et **l'efface systématiquement**
  (`finally`), succès comme échec.
- Le broker fixe `cwd=<dépôt>` pour **tous** ses appels gws, pas seulement les
  uploads : le bac à sable fichiers de gws devient le répertoire de dépôt au
  lieu du dépôt git.
- Le chemin est dérivé de `gwsa_root()` des deux côtés — gateway et broker
  partagent déjà `GWSA_ROOT` (jeton, pidfile, `usage.jsonl`), un couloir
  (stable / dev, fiche 0023) a son dépôt.
- `parents` reste dans `--json` : c'est le seul endroit que `policy-check.py`
  lit pour vérifier la zone d'écriture. Les zones Drive s'appliquent donc au
  dépôt de contenu exactement comme à la création d'un fichier vide.
- Le répertoire commence par un point : les trois énumérateurs de profils
  (`gateway/profiles.py`, `bin/gwsa`, `admin/server.js`) filtrent sur
  `ALIAS_RE`, il n'apparaît jamais comme un compte.

## Options considérées

### Option A — Fichier temporaire dans `/tmp`, chemin absolu

| Dimension | Évaluation |
|---|---|
| Simplicité | Maximale (une dizaine de lignes, zéro coordination) |
| Fonctionne | Non — gws refuse le chemin hors cwd |

**Rejetée** : ne marche pas. C'est la contrainte n° 2 qui a fermé cette porte.

### Option B — Répertoire de dépôt partagé + cwd du broker (retenue)

| Dimension | Évaluation |
|---|---|
| Protocole broker | Inchangé (toujours « une liste d'arguments ») |
| Doctrine ADR-0002 | Respectée — la gateway écrit un fichier, elle n'exécute toujours pas gws |
| Sécurité | Bac à sable de gws **rétréci** : du dépôt git au seul répertoire de dépôt |
| Échec sur broker obsolète | Explicite (`outside the current directory`), jamais silencieux |

**Pour :** aucune évolution de protocole, donc aucune négociation de version
entre une gateway neuve et un broker déjà lancé ; et un cwd de gws plus étroit
qu'avant pour *toutes* les commandes. **Contre :** la responsabilité est
partagée (la gateway écrit le fichier, le broker fixe le cwd) — deux morceaux
de code doivent s'accorder sur un chemin. Le couplage existe déjà (`GWSA_ROOT`)
et un test hermétique le verrouille.

### Option C — Étendre le protocole du broker (champ `media`)

Le contenu voyagerait dans la requête RPC ; le broker écrirait le fichier,
ajouterait `--upload`, puis nettoierait.

| Dimension | Évaluation |
|---|---|
| Cohérence | La meilleure : le broker possède tout ce que gws touche |
| Protocole | Change — un broker **déjà lancé** (ancien code) ignore `media`… |
| Échec sur broker obsolète | …et crée un document **vide sans rien signaler** |

**Pour :** propriété unique du fichier média. **Contre :** le broker est un
démon qui survit aux mises à jour du code (`deploy-local.sh` le recycle
justement pour ça) : un champ ignoré en silence produit une perte de données
silencieuse. Il faudrait une négociation de capacités (ou une commande
distincte) pour rendre l'échec explicite — de la mécanique en plus pour un
gain de confiance nul ici (gateway et broker sont le même utilisateur, le même
code déployé, et le broker fait déjà confiance aux arguments de la gateway
sous réserve de policy). **Rejetée pour l'instant** ; à reconsidérer si le
broker devait un jour servir des clients moins fiables que la gateway locale.

### Option D — Créer vide puis écrire via l'API Docs

`drive files create` (vide) puis `docs documents batchUpdate` /
`gws docs +write`.

| Dimension | Évaluation |
|---|---|
| Policy | Bloquée en pratique : `docs` non déclaré = refus (default-deny) |
| Atomicité | Deux appels — état intermédiaire « document vide » en cas d'échec |
| Rendu | Texte brut seulement : ni titres, ni listes, ni gras |

**Rejetée.**

## Conséquences

- Devient possible : déposer un livrable **rédigé** sur le bon compte, en une
  requête, converti en Google Doc (markdown par défaut quand la cible est un
  type Google — c'est le format dans lequel les agents rédigent).
- Devient plus sûr : gws s'exécute désormais depuis un répertoire de dépôt
  vide plutôt que depuis le dépôt git ; un `--upload` fabriqué ne peut plus
  désigner un fichier du projet.
- Devient plus exigeant : un broker lancé **avant** cette version continue de
  servir l'ancien code et refusera l'upload (`outside the current directory`).
  Remède : `gwsa broker stop` (il redémarre tout seul au prochain appel) —
  c'est déjà ce que fait `scripts/deploy-local.sh`.
- Le contenu écrit par le LLM touche le disque, en clair, le temps d'un appel
  (0600, dans un répertoire 0700, effacé en `finally`). C'est le même niveau
  d'exposition que `usage.jsonl` qui journalise déjà les arguments des
  commandes, et bien moindre que les credentials du même répertoire.
