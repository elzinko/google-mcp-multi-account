# Le modèle de policy — qui a le droit de faire quoi

Une **policy**, c'est la liste de ce qu'un compte connecté a le droit de faire :
lire ses mails ? préparer des brouillons ? écrire dans Drive, et où exactement ?
La règle de base est délibérément prudente — **ce qui n'est pas explicitement
autorisé est refusé** — et c'est *vous* qui élargissez, jamais l'assistant.

Concrètement, chaque compte porte un petit fichier
`~/.config/gws-accounts/<alias>/policy.json`, vérifié par
[`policy-check.py`](https://github.com/elzinko/google-mcp-multi-account/blob/main/scripts/policy-check.py)
**avant chaque commande** — aussi bien quand vous tapez `gma …` que quand
l'assistant passe par le MCP. `gma add` en écrit une prudente d'office : un compte
tout neuf est donc déjà bridé. Pour l'usage courant, voir
[Utiliser au quotidien](usage.md).

## Default-deny, par service

**Un service absent de la policy est refusé** (sauf `auth` / `schema`,
introspection locale) — y compris en lecture. Un service présent est *fail
closed* : seule une catégorie explicitement à `true` passe. `gma add` écrit
une policy prudente automatiquement, si bien qu'un profil frais est restreint
d'emblée. Conséquence : les services non modélisés par l'admin (chat, meet,
people, slides, forms, script…) sont refusés par défaut — pas d'action visible
de l'extérieur qui échappe au contrôle.

- **Drive** — par zones : lecture partout, écriture uniquement sous les dossiers
  autorisés (sous-dossiers compris — remontée des parents via l'API). Modes
  hérités : `open`, `readonly`, `restricted`.
- **Gmail** — catégories `read`, `drafts`, `send`, `labels`, `update`, `delete`,
  `settings`. Le combo gagnant : *brouillons sans envoi* — le LLM prépare, tu envoies.
- **Agenda / Keep / autres services modélisés** — `read`, `create`, `update`,
  `delete`, `share`.

```bash
gma policy mw allow "LLM"        # Drive : zone PERMANENTE sous le dossier « LLM »
gma policy mw show               # affiche la policy complète du profil
gma mw drive files create --json '{"name":"x"}'   # ✗ refusé (pas de parent autorisé)
gma mw gmail users messages send --json '…'       # ✗ refusé si "send": false
gma policy mw clear              # Drive repasse en open (autres services inchangés)
```

## Zones temporaires — le flux d'élicitation Drive

Par défaut un profil en `zonesOnly` n'a le droit d'écrire *nulle part*. Quand
un LLM veut écrire quelque part, il se heurte à un refus qui lui dit quoi
demander ; c'est **toi** qui accordes, pour une durée limitée (défaut 8 h,
expiration automatique — donc à re-demander à chaque session de travail) :

```bash
gma grant coloc "Compta 2026" 4   # écriture sous ce dossier pendant 4 h
gma grants coloc                  # autorisations temporaires actives
gma grant coloc revoke <folderId> # révoquer avant l'expiration
```

Chaque refus est journalisé et invite le LLM à *demander* l'élargissement —
l'élicitation, encore. *Limite assumée : c'est le wrapper qui contrôle, pas
Google — le seul verrou 100 % côté Google serait le scope `drive.file`.*

## Droits par session — le grain fin (ADR-0007)

La policy et les zones ci-dessus sont le **plancher du poste**. Par-dessus,
chaque **conversation** (session LLM) porte ses **propres** droits, signés et
limités dans le temps — une autre conversation n'en hérite pas. C'est le grain
le plus fin : par **service × opération × ressource**.

- L'humain ouvre une session (`gma session open`) — un geste **signé** (Touch ID
  sous strongauth) qui rend un **jeton** ; l'assistant présente ce jeton à
  chaque appel (sans jeton : aucun accès aux données, seulement la demande de
  création).
- Chaque octroi de capacité est **signé** lui aussi — jamais un élargissement
  silencieux :

```bash
gma session open                                    # crée une session signée → jeton
gma session grant-capability <jeton> mw gmail read  # cette session : lecture Gmail
gma session grant-capability <jeton> mw drive write "Compta 2026"  # écriture zonée
gma session list                                    # sessions actives + leur config
```

- **Droits effectifs = policy compte ∩ manifeste projet ∩ capacités session**
  (intersection, *fail closed*). Hors dépôt git (pas de manifeste), `policy ∩
  session` ; mais un manifeste **altéré** referme tout (anti-downgrade).
- Les **sous-agents** héritent d'un sous-ensemble du parent (jamais plus) et ne
  peuvent pas s'élargir seuls ; le parent révoque toute sa descendance d'un geste.

Détail de conception : [ADR-0007](adr/ADR-0007-droits-par-session.md).

Durcissements de ce modèle déjà tranchés : voir la fiche backlog
[0002](https://github.com/elzinko/google-mcp-multi-account/blob/main/features/done/0002-durcir-modele-policy-default-deny.md) (default-deny
vérifié et testé) et [threat-model.md](threat-model.md).
