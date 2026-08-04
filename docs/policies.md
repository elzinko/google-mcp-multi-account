# Le modèle de policy — qui a le droit de faire quoi

Chaque profil peut porter une policy (`~/.config/gws-accounts/<alias>/policy.json`,
appliquée par [`scripts/policy-check.py`](https://github.com/elzinko/google-mcp-multi-account/blob/main/scripts/policy-check.py) avant
chaque commande, côté `gwsa` comme côté gateway MCP). Utilisation générale :
[usage.md](usage.md).

## Default-deny, par service

**Un service absent de la policy est refusé** (sauf `auth` / `schema`,
introspection locale) — y compris en lecture. Un service présent est *fail
closed* : seule une catégorie explicitement à `true` passe. `gwsa add` écrit
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
gwsa policy mw allow "LLM"        # Drive : zone PERMANENTE sous le dossier « LLM »
gwsa policy mw show               # affiche la policy complète du profil
gwsa mw drive files create --json '{"name":"x"}'   # ✗ refusé (pas de parent autorisé)
gwsa mw gmail users messages send --json '…'       # ✗ refusé si "send": false
gwsa policy mw clear              # Drive repasse en open (autres services inchangés)
```

## Zones temporaires — le flux d'élicitation Drive

Par défaut un profil en `zonesOnly` n'a le droit d'écrire *nulle part*. Quand
un LLM veut écrire quelque part, il se heurte à un refus qui lui dit quoi
demander ; c'est **toi** qui accordes, pour une durée limitée (défaut 8 h,
expiration automatique — donc à re-demander à chaque session de travail) :

```bash
gwsa grant coloc "Compta 2026" 4   # écriture sous ce dossier pendant 4 h
gwsa grants coloc                  # autorisations temporaires actives
gwsa grant coloc revoke <folderId> # révoquer avant l'expiration
```

Chaque refus est journalisé et invite le LLM à *demander* l'élargissement —
l'élicitation, encore. *Limite assumée : c'est le wrapper qui contrôle, pas
Google — le seul verrou 100 % côté Google serait le scope `drive.file`.*

Durcissements de ce modèle déjà tranchés : voir la fiche backlog
[0002](https://github.com/elzinko/google-mcp-multi-account/blob/main/features/done/0002-durcir-modele-policy-default-deny.md) (default-deny
vérifié et testé) et [threat-model.md](threat-model.md).
