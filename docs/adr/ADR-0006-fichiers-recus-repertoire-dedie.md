# ADR-0006 : Les fichiers reçus atterrissent dans un répertoire de téléchargement dédié

**Statut :** Accepté
**Date :** 2026-07-29
**Décideurs :** Thomas (PO)

## Contexte

La fiche 0043 fait entrer des fichiers **descendants** dans le système :
`gmail_attachment_get` matérialise une pièce jointe sur le disque local.
L'ADR-0003 a réglé le sens **montant** (contenu écrit par le LLM → dépôt
`.uploads` → gws) ; rien ne cadrait le sens inverse.

Une pièce jointe est un **contenu tiers** : rédigée par l'expéditeur du mail,
pas par l'utilisateur ni par le LLM. Le nom de fichier comme le contenu sont
potentiellement hostiles. Et le paramètre `filename` du tool est fourni par le
LLM — c'est-à-dire, en cas d'injection de prompt via un mail lu, par
l'attaquant lui-même.

## Décision

**Créer un répertoire de téléchargement dédié, `<GWSA_ROOT>/.downloads`
(0700), seule destination possible des fichiers reçus.**

- Le tool n'accepte **aucun chemin de destination** : seulement un `filename`
  indicatif, réduit à un nom de base assaini (jamais caché, jamais vide,
  jamais de séparateur).
- **Jamais d'écrasement** : création en `O_CREAT|O_EXCL` (0600), suffixe
  numérique si le nom existe déjà. Deux téléchargements = deux fichiers.
- Le chemin final est **renvoyé** à l'appelant : c'est le client MCP (Claude
  Code, l'humain) qui décide ensuite de copier le fichier dans un projet —
  un geste hors gateway, sous ses propres permissions.
- Symétrie côté montant : `drive_upload` refuse de lire sous `GWSA_ROOT`
  (tokens, credentials, policies) — à l'exception de `.downloads`, pour que
  « recevoir une PJ puis la déposer sur Drive » reste un enchaînement direct.
- Le point en tête (`.downloads`) le tient hors des énumérations de profils,
  comme `.uploads` (ADR-0003).

## Options considérées

### Option A — Paramètre `output_path` libre

| Dimension | Évaluation |
|---|---|
| Ergonomie | La meilleure (le fichier arrive là où on le veut) |
| Sécurité | Écriture arbitraire d'un contenu attaquant-contrôlé : un mail piégé qui convainc le LLM d'écrire `~/Library/LaunchAgents/x.plist` ou `~/.zshrc` devient un vecteur d'exécution |

**Rejetée** : le couple « contenu tiers + chemin choisi par le LLM » est
exactement ce que le modèle de menace du projet interdit.

### Option B — Répertoire dédié, chemin renvoyé (retenue)

| Dimension | Évaluation |
|---|---|
| Sécurité | Surface d'écriture = un répertoire 0700, noms uniques, zéro écrasement |
| Ergonomie | Un `cp` de plus pour l'appelant — chemin fourni, geste trivial |
| Cohérence | Miroir exact de `.uploads` (ADR-0003) : un couloir par sens |

### Option C — Renvoyer le binaire en base64 dans la réponse MCP

| Dimension | Évaluation |
|---|---|
| Simplicité | Aucun fichier local |
| Praticabilité | Un logo de 500 Ko = ~700 Ko de base64 injectés dans le contexte du LLM ; un catalogue PDF le fait déborder |

**Rejetée** : le contenu doit finir sur le disque de toute façon ; le faire
transiter par le contexte du modèle n'apporte que de la perte.

## Conséquences

- Devient possible : récupérer une pièce jointe (logo, catalogue, PDF) et la
  réutiliser — y compris la re-téléverser sur Drive via `drive_upload`.
- Devient impossible par construction : écraser un fichier existant ou écrire
  hors de `.downloads` depuis un tool MCP.
- Le répertoire n'est jamais purgé automatiquement : les fichiers s'y
  accumulent jusqu'à un ménage humain (même statut que `usage.jsonl` —
  candidat au ménage de la fiche 0028).

## Source de `drive_upload` — liste blanche (défaut-deny)

Symétrie de `.downloads` côté montant : la **source** d'un `drive_upload` est
restreinte à une **liste blanche** de dossiers, pas au disque entier. Sinon un
`drive_upload("~/.ssh/id_rsa", <zone accordée>)` induit par injection de prompt
exfiltrerait un secret local — **atteignable par le seul MCP, sans shell**.

Dossiers autorisés en lecture :

- `<GWSA_ROOT>/.downloads` — toujours (re-téléverser une PJ reçue) ;
- ceux déclarés dans `GWSA_UPLOAD_ROOTS` (chemins absolus séparés par
  `os.pathsep`, `:` sous Unix).

Volontairement **hors du dépôt git** (un livrable n'a pas à vivre dans les
sources) et **hors de `GWSA_ROOT`** (tokens) : l'humain ouvre explicitement les
dossiers d'où le LLM peut lire. Par défaut la liste est vide → seul
`.downloads` est lisible ; déposer le fichier à téléverser dans `.downloads`,
ou ouvrir son dossier. Un garde dur refuse en outre toute lecture sous
`GWSA_ROOT` (hors `.downloads`) même si `GWSA_UPLOAD_ROOTS` l'englobait par
erreur.

Une **liste noire** de chemins sensibles a été écartée (fragile, jamais
exhaustive, fausse assurance). Défense en profondeur au-delà de la liste
blanche : l'écriture Drive exige de toute façon une **zone active** (grant
humain, jamais accordée par le LLM) et l'appel reste **visible** dans la trace.
