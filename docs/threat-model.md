# Modèle de menace — google-mcp-multi-account

Document frère : architecture détaillée → [architecture.md](architecture.md).

## Objectif

Permettre à un ou plusieurs clients LLM (Claude Desktop, Cursor, Claude Code, …)
d’accéder à **plusieurs comptes Google** en local, **sans faire confiance au LLM
par défaut** : lecture/écriture limitées par policy, verrous, zones Drive, et
élicitation humaine pour élargir l’accès.

## Surfaces de confiance

| Composant | Rôle | Confiance |
|-----------|------|-----------|
| Humain | unlock, grant, policy, OAuth | Racine de confiance |
| Admin `127.0.0.1:4877` | Cockpit | Processus local ; pas d’auth app |
| `bin/gma` + `scripts/policy-check.py` | Garde-fous CLI | Appliqués si on passe par eux |
| `gateway/` + `bin/google-mcp` | Porte d’entrée MCP | Même policy/lock ; tools curatés (pas de send) |
| `gws` + `~/.config/gws-accounts/` | Tokens + appels Google | **Capacité réelle** d’accès aux données |

## Phase 1 (actuelle) — ce qui est garanti

- Profil créé via `gma add` → **policy prudente** (Drive zones vides, Gmail sans envoi, services non listés refusés).
- Service absent de `policy.json` → **default-deny** (sauf `auth` / `schema`).
- Profil verrouillé → refus via `gma` **et** via MCP.
- Tools MCP : Gmail lecture + brouillons + pièce jointe (→ `.downloads`), Drive lecture (métadonnées + contenu) + create/copy/upload + **update** (remplacement de contenu, fichiers non-natifs seulement) **sous zones** ; **partage** lecture/écriture (`drive_permissions_create/list/delete`) — jamais de partage **public** (`type` fixé à `user`) ; **pas** d’envoi Gmail, de suppression définitive, ni de **transfert de propriété** (retiré — PR dédiée non prête).
- ⚠ **Partage** (`drive_permissions_*`) n’est gardé que par la policy `drive.share:true` (flag **persistant**), **pas** par les zones ni par un grant de session : une fois `share` activé, l’agent peut partager tout fichier possédé vers tout email (jamais public — `type=user`). **Durcissement à trancher** (revue sécurité F2) : grant de session pour partager.
- `access_request` propose unlock/grant **sans les exécuter**.
- Touch ID (`gma strongauth`) : présence physique pour unlock/grant (chemins absolus `/usr/bin/swift` + `/usr/bin/swiftc` + scripts repo — jamais via le PATH).

## Phase 1 — ce qui n’est **pas** garanti

Un agent avec **shell libre** et accès filesystem peut encore :

```bash
GOOGLE_WORKSPACE_CLI_CONFIG_DIR=~/.config/gws-accounts/<alias> gws …
```

et contourner lock, policy, journal et MCP. L’élicitation contrôle le **comportement
coopératif** ; elle ne retire pas la **capacité** tant que les credentials sont
utilisables par `gws` hors gateway.

**Mitigation recommandée** (clients avec shell : Claude Code, Cursor Agent) :

- Chemin supporté pour les données Google = **MCP uniquement** (`bin/google-mcp`).
- Restreindre / refuser dans les permissions bash : `gws`, `GOOGLE_WORKSPACE_CLI_CONFIG_DIR=…`,
  lecture/écriture de `~/.config/gws-accounts/`.
- Ne pas mettre `gws` dans le PATH de l’agent si possible ; l’humain garde `gma` pour l’admin.

## Phase 2 A (actuelle) — broker loopback

- MCP → gateway → **broker** (`127.0.0.1:4878`, token `~/.config/gws-accounts/.broker-token`) → `gws`.
- Auto-start du broker au premier tool MCP si besoin (`bin/google-broker`).
- Le broker re-applique lock + policy avant `gws`.

## Phase 2 A — ce qui n’est **pas** encore garanti

Les credentials restent dans `~/.config/gws-accounts/`. Un agent avec shell libre
peut toujours appeler `gws` directement. Mitigation : restreindre le shell ;
évolution = vault ([features/0003](https://github.com/elzinko/google-mcp-multi-account/blob/main/features/0003-vault-credentials-hors-perimetre-agent.md)).

## Email = métadonnée d'identité (hors verrou)

L'email d'un profil reste lisible même verrouillé — c'est la **seule**
métadonnée exposée (diagnostic IAM de `setup_status`, SECURITY.md). Depuis
[ADR-0002](adr/ADR-0002-email-metadonnee-hors-verrou.md), il vient d'un
fichier `.email` écrit au geste humain `gma add` (backfill : `gma list`,
admin) — **jamais** d'une exécution `gws`. Invariant testé : verrou ⇒ zéro
exécution gws ; aucun `GOOGLE_WORKSPACE_CLI_CONFIG_DIR` dans `gateway/`
hors `broker_server.py`.

## Contenu déposé sur Drive (répertoire de dépôt)

`drive_create(content=…)` matérialise le texte dans
`~/.config/gws-accounts/.uploads/` (0700) le temps d'un appel `gws --upload` :
c'est la seule façon de passer un média à `gws`, qui refuse par ailleurs tout
chemin hors de son répertoire courant ([ADR-0003](adr/ADR-0003-contenu-drive-via-depot-broker.md)).
Fichier en 0600, effacé en `finally` (succès comme échec) — exposition
comparable à `usage.jsonl`, qui journalise déjà les arguments des commandes.
Effet de bord favorable : `gws` s'exécute désormais **depuis ce répertoire**,
donc son bac à sable fichiers n'est plus le dépôt git. Les zones Drive
s'appliquent inchangées : `parents` reste dans `--json`, seul endroit que
`policy-check.py` lit pour valider la destination.

## Fichiers reçus (répertoire de téléchargement)

`gmail_attachment_get` matérialise une pièce jointe — **contenu tiers**,
potentiellement hostile — dans `~/.config/gws-accounts/.downloads/` (0700),
seule destination possible ([ADR-0006](adr/ADR-0006-fichiers-recus-repertoire-dedie.md)).
Le tool n'accepte **aucun chemin de destination** : seulement un `filename`
indicatif, réduit à un nom de base assaini (jamais un séparateur, jamais caché,
jamais vide). Écriture en `O_CREAT|O_EXCL` (0600), suffixe numérique si le nom
existe déjà — **jamais d'écrasement**. Symétrie avec le sens montant :
`drive_upload` refuse de lire sous `GWSA_ROOT` (tokens, credentials, policies),
à l'exception de `.downloads` (re-téléverser une PJ reçue). Le chemin final est
renvoyé à l'appelant, qui décide ensuite d'un éventuel `cp` — hors gateway.

Côté montant, la **source** de `drive_upload` est restreinte à une **liste
blanche** (`.downloads` + les dossiers déclarés dans `<GWSA_ROOT>/.upload-roots`
ou `GWSA_UPLOAD_ROOTS`), pas au disque entier : le LLM ne peut pas lire un
chemin arbitraire (ex. `~/.ssh/id_rsa`) et l'exfiltrer vers une zone active —
défaut-deny, l'humain seul ouvre les dossiers lisibles (le fichier `.upload-roots`
n'est pas écrivable par un tool) —
[ADR-0006](adr/ADR-0006-fichiers-recus-repertoire-dedie.md).

## Phase 2.1 (prévue) — vault

Credentials hors lecture agent ; seule la socket broker reste utile.

## Phase 1 — profils legacy

Un profil **sans** `policy.json` (créé avant ce durcissement) reste non filtré
par le checker tant que tu n’en poses pas une. Pour basculer : préréglage
« prudent » dans l’admin, ou recopier `gateway/default_policy.py`.

## Journal d’audit

`~/.config/gws-accounts/usage.jsonl` — appels autorisés (`decision:ok`), refus
de policy et refus de verrou (`decision:refus`, `reason:locked`), sur les trois
chemins (`gma`, broker, fail-fast gateway). Champ `client` via `GWSA_CLIENT`
(`mcp`, `claude-code`, `cli`, …). Spoofable : utile pour le debug, pas une identité forte.
