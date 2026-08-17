---
id: 0046
title: CLI locale pour déployer des sandboxes temporaires (branche / worktree)
type: feature
priority: P2
version:
epic:
status: in-progress
ready: 2026-07-28
pr:
created: 2026-07-28
updated: 2026-07-28
---

## Contexte / Problème

Le déploiement **stable** (`deploy-local.sh` + `update.sh`) exige un **tag semver**
et bascule `current` — adapté à la prod locale, pas à l'essai d'une **branche
feature** ou d'une PR.

La fiche [[0027]] pose le besoin (`--as sha-…`, jamais `current`) mais n'est pas
implémentée. Aujourd'hui, brancher une version de dev demande plusieurs scripts
à enchaîner à la main (`deploy-local`, `install-claude-desktop`, ports, noms
d'entrée) — erreur fréquente : mélange de brokers (fiche [[0025]]).

Objectif : **une commande** pour figer le répertoire git courant dans une
sandbox jetable, lister ce qui est branché où, et voir ce qui tourne — **sans
toucher** au stable (4878 / `current`).

## Proposition

### Commandes (`mag sandbox …`)

| Commande | Effet |
|---|---|
| `mag sandbox deploy [--wire …]` | Figé depuis **HEAD** du dépôt courant (arbre sale → avertissement, archive = fichiers commités seuls). Ne modifie **pas** `current`. Écrit `VERSION` + `.sandbox.json`. Id = `<slug-branche>-<sha>[-dirty]` (pas de préfixe `dev-`). Sans `--wire` : affiche la procédure humaine. Avec `--wire` : branche une entrée MCP **suffixée** (`google-multi-account-<id>`) dans Desktop / Code / Cursor (ne touche pas l'entrée stable). |
| `mag sandbox wire [id] [--wire …]` | Branche les clients MCP sur une sandbox déjà déployée (même entrée suffixée). Sans id → sandbox de la branche courante. |
| `mag sandbox wire [id] --remove […]` | Unwire sélectif : retire l'entrée suffixée des clients listés (`desktop`, `code`, `cursor`, ou `all` si flag seul). **Ne supprime pas** le répertoire sandbox. Ne touche jamais `google-multi-account`. |
| `mag sandbox remove [id]` | **Nucléaire** : unwire tous les clients, arrête broker/admin, **supprime** le répertoire sous `~/.local/share/google-mcp/`. Refuse `current` et archives sans manifeste sandbox. Sans id → sandboxes de la branche courante. |
| `mag sandbox list` | Versions sous `~/.local/share/google-mcp/`, entrées MCP trouvées (Claude Desktop, Cursor), ports broker/admin, binaire. |
| `mag sandbox status [id]` | Par sandbox (ou toutes) : broker (pid/port), admin (port), version. |

`--wire` / `--remove` : `all` (défaut si flag seul) ou liste `desktop,code,cursor` (alias `cd` / `cc` / `claude-desktop` / `claude-code`). Ports via `GWSA_DESKTOP_CONFIG` / `GWSA_CURSOR_CONFIG` pour les tests.

**Aide CLI (référence)** : `mag sandbox --help` — documente `deploy --wire`, `wire`, `wire --remove` (sélectif) vs `remove` (nucléaire), et les overrides d'env.

Alias bash : `scripts/sandbox.sh`. Alias déprécié : `mag couloir` / `scripts/couloir.sh` (hint puis forward).

Compat : les anciens déploiements avec `.couloir.json` restent lisibles par `list` / `status` ; les nouveaux écrivent `.sandbox.json`. Anciens ids `dev-<slug>-…` restent utilisables pour remove/wire/status (pas de renommage auto).

### Matrice de ports (ne pas casser l'existant)

| Couloir | Rôle | Broker (`GWSA_BROKER_PORT`) | Admin (`GWSA_ADMIN_PORT`) | `GWSA_ROOT` | Entrée MCP type |
|---|---|---|---|---|---|
| **stable** | prod locale via `current` | **4878** (défaut) | **4877** (défaut) | `~/.config/gws-accounts` | `google-multi-account` |
| **dev clone** | working tree direct | **4880** | 4877 (partagé — un seul admin à la fois) | `~/.config/gws-accounts-dev` | `google-multi-account-dev` |
| **tests** | suite hermétique | **4879**, 4977, 4988… | — | temp | — |
| **épinglé tag** | version figée nommée | **4881+** (choisi à l'install) | 4877 ou 4878+ | partagé stable | `google-multi-account-v0.1.0` |
| **temp sandbox** (`sandbox deploy`) | branche / PR jetable | **4882+** (auto, premier libre) | **4879+** (auto, évite 4877 et broker 4878) | partagé stable | `google-multi-account-<id>` |

Règles :

1. **Ne jamais** modifier `current` ni recycler le broker 4878 depuis `sandbox deploy`.
2. Un port broker = un broker = un code (fiche 0025).
3. Admin : v1 documente « un admin actif » ; `GWSA_ADMIN_PORT` permet des admins
   parallèles plus tard (pidfile `.admin-<port>.pid`).
4. Les comptes restent sur `GWSA_ROOT` stable sauf clone de développement explicite.

### Étiquette de version

- Tag release : contenu de `VERSION` = tag (`v0.2.0`).
- Temp sandbox : `feat/0040-sessions-vault@10675c4 (dev)` — affiché CLI, admin, `initialize`.

### Procédure humaine (après `sandbox deploy`)

Sans `--wire`, le script imprime (ne pas exécuter à la place de l'humain) :

1. Brancher Claude Desktop : `install-claude-desktop.sh --name … --port …` sur la **copie déployée** (jamais le clone) — ou `mag sandbox wire`.
2. Idem Cursor (`~/.cursor/mcp.json`) si besoin.
3. Redémarrer le client MCP.
4. Vérifier : `mag sandbox status <id>` ou version dans l'admin.

Avec `deploy --wire` / `sandbox wire` : branchement auto de l'entrée suffixée ; checklist courte (redémarrer clients, admin sandbox, vérifier).

## Scénarios BDD

```gherkin
Scenario: déployer une branche feature sans toucher current
  Given je suis sur la branche feat/foo avec HEAD propre
  When j'exécute mag sandbox deploy --dev
  Then une copie existe sous ~/.local/share/google-mcp/feat-foo-<sha>/
  And current pointe toujours sur la version stable précédente
  And le script affiche une commande install-claude-desktop avec un port != 4878

Scenario: lister les sandboxes branchées
  Given une entrée google-mcp dans Claude Desktop sur le port 4882
  When j'exécute mag sandbox list
  Then la sortie mentionne le binaire, le port 4882 et le fichier de config

Scenario: statut broker et version
  Given une sandbox dev déployée avec broker démarré
  When j'exécute mag sandbox status feat-foo-<sha>
  Then la sortie indique broker en route sur le port du manifeste
  And la version affichée contient "(dev)"

Scenario: unwire sélectif sans supprimer
  Given une sandbox branchée sur Desktop et Cursor
  When j'exécute mag sandbox wire --remove desktop
  Then l'entrée suffixée disparaît de Claude Desktop seulement
  And le répertoire ~/.local/share/google-mcp/<id>/ existe encore
  And l'entrée stable google-multi-account est intacte

Scenario: stable intact
  Given le broker stable écoute sur 4878
  When j'exécute mag sandbox deploy --dev
  Then mag broker status sur le déploiement stable signale toujours le broker 4878
```

## Critères d'acceptation

- [x] Fiche backlog + branche `feat/v2-local-deploy`.
- [x] `mag sandbox deploy|list|status` prototype (scripts/sandbox.sh).
- [x] `sandbox deploy` ne touche pas `current`.
- [x] Ports auto ≥ 4882 (broker) et ≥ 4879 (admin) pour les temp sandbox.
- [x] Version visible dans l'admin (bandeau) et dans la sortie CLI.
- [x] Verb canonique `sandbox` ; `couloir` alias déprécié (hint + forward).
- [x] Nouveau manifeste `.sandbox.json` ; lecture compat `.couloir.json`.
- [ ] Scanner les configs Claude Code / Cursor projet (v2).
- [x] `sandbox remove [id]` (+ sans id = branche courante ; `--all` si plusieurs sha)
- [x] `sandbox deploy --wire` / `sandbox wire` : entrée MCP suffixée (stable intact) ; unwire sélectif via `wire --remove` ; nucléaire à `remove`
- [ ] `setup_status` / `mag doctor` : dérive config vs déployé (fiche 0026).
- [x] Tests hermétiques dans `scripts/test.sh`.

## Notes

- Découle de [[0027]] (commit non taggé) et [[0026]] (savoir qui répond).
- `deploy-local.sh` reste le chemin **stable** ; `sandbox deploy` est le chemin **jetable**.
- **PATH** : le `mag` du PATH (ex. Homebrew → `current`, v0.2.1) n'expose pas encore `sandbox` — depuis le worktree utiliser `./bin/mag sandbox …`, ou déployer la branche puis le `mag` du répertoire sandbox sous `~/.local/share/google-mcp/<id>/bin/mag`.
- Inspiration externe : city-guided (`APP_VERSION` + bandeau admin), ezk-preview
  (URL de démo par branche) — patterns de label `branch@sha`, pas de merge auto.

## Implémenté (prototype v1)

- `scripts/sandbox.sh` — deploy / list / status / remove / wire (`--wire`, `--remove`).
- Id sandbox = `<slug>-<sha>[-dirty]` ; anciens `dev-<slug>-…` toujours reconnus.
- `mag sandbox` — wrapper dans `bin/mag` (`couloir` = alias déprécié).
- Admin : `GET /api/meta` + `GET /api/dev` + bandeau version / branche / sha ; panneau
  Développement (sandboxes, ports, MCP) ; `GWSA_ADMIN_PORT` lu par `admin/server.js`.
  Setup affiche le **projet GCP** (pas la version MCP).
