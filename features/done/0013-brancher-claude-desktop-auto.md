---
id: 0013
title: Brancher le serveur MCP dans Claude Desktop en un geste (script idempotent)
type: feature
priority: P2
version:
epic:
status: shipped
ready: 2026-07-24
pr: "#15"
created: 2026-07-24
---

## Contexte / Problème

Brancher le serveur MCP dans Claude Desktop est aujourd'hui **manuel** : l'utilisateur
doit ouvrir `~/Library/Application Support/Claude/claude_desktop_config.json`, y coller
un bloc JSON, et **remplacer `/ABS/PATH/…` par le chemin absolu de son clone**
(cf. [docs/mcp-setup.md](../docs/mcp-setup.md)). Trois frictions :

1. **Le chemin absolu** est la première cause d'erreur (copié de travers, relatif, clone
   ailleurs) — le serveur ne démarre pas et le diagnostic est opaque côté Desktop.
2. **Éditer un JSON à la main** risque d'**écraser d'autres serveurs MCP** déjà présents,
   ou de casser le fichier (virgule, accolade) sans backup.
3. C'est un geste **non reproductible** : après un `git pull` qui déplace le binaire, ou
   un second poste, il faut tout refaire à la main.

Le reste du projet règle ce genre de geste par un **script idempotent** (cf.
`provision-gcp.sh`, `sync-skills.sh`) — pas par une manip documentée.

## Proposition

Un script `scripts/install-claude-desktop.sh` qui **fusionne** l'entrée
`google-multi-account` dans la config Claude Desktop, dans le moule des scripts existants
(helpers `step/ok/warn/die`, français, `/usr/bin/python3`, idempotent) :

- résout **seul** le chemin absolu de `bin/google-mcp` (relatif à sa propre position) ;
- **merge** l'entrée dans `mcpServers` **sans toucher** aux autres serveurs ni au reste
  du fichier (JSON re-sérialisé proprement) ;
- **backup horodaté** + **écriture atomique** (`os.replace`) avant toute modification ;
- détecte le fichier config selon l'OS (macOS / Linux `XDG`), surchargeable via `--config` ;
- `--print` (dry-run : montre le résultat sans écrire), `--name` (nom d'entrée custom) ;
- **idempotent** : relançable sans risque (`unchanged` si déjà à jour, `mise à jour` si le
  chemin a bougé) ;
- **refuse proprement** un JSON invalide (message clair, exit ≠ 0, fichier intact).

`docs/mcp-setup.md` mène par le script, garde le JSON manuel en repli. Le geste
d'exécution reste **humain** (le LLM écrit le script, ne l'exécute pas — il touche une
config machine hors repo).

> Un **prototype fonctionnel** existe déjà sur la branche (script + doc + validation
> manuelle sur configs temporaires). Le sprint le **durcit** : un **test hermétique**
> dans `scripts/test.sh` (sans Claude Desktop réel, sur config temporaire) qui verrouille
> les invariants — le maillon manquant aujourd'hui.

## Critères d'acceptation

- [ ] `scripts/install-claude-desktop.sh` existe, exécutable, `--help` documente l'usage.
- [ ] Config **absente** → crée le fichier avec la seule entrée `google-multi-account`.
- [ ] Config **avec d'autres serveurs MCP** → l'entrée est ajoutée **sans perdre** les
      autres serveurs ni les autres clés (ex. `globalShortcut`).
- [ ] **Relance** sans changement → statut `unchanged`, **aucune écriture**.
- [ ] Entrée présente sur un **ancien chemin** → **mise à jour** du `command` + backup.
- [ ] `command` pointe sur le **chemin absolu** de `bin/google-mcp` du clone courant ;
      `env.GWSA_CLIENT = claude-desktop`.
- [ ] **Backup horodaté** créé avant toute modification ; écriture **atomique**.
- [ ] `--print` n'écrit **rien** et affiche le contenu qui serait écrit.
- [ ] **JSON invalide** en entrée → message d'erreur clair, **exit ≠ 0**, fichier **intact**.
- [ ] Un **test hermétique** dans `scripts/test.sh` couvre : création, préservation d'un
      serveur tiers, idempotence, mise à jour de chemin, rejet JSON invalide — sans
      dépendre d'une install Claude Desktop réelle (config en dossier temporaire).
- [ ] [docs/mcp-setup.md](../docs/mcp-setup.md) mène par le script (JSON manuel en repli).

## Notes

- Frontière CLAUDE.md : **le LLM guide** (via `setup_status` / `next_actions`), **l'humain
  exécute** le script — jamais le LLM (config machine hors repo). Aligné avec la doctrine
  « next_actions à proposer, pas à lancer ».
- Cohérent avec l'esprit `provision-gcp.sh` : idempotent, backup, relançable.
- Hors périmètre v1 : Cursor et Claude Code (déjà couverts par `claude mcp add` /
  `~/.cursor/mcp.json` dans la doc) — le script vise Claude Desktop, le cas le plus manuel.
  Extension multi-clients possible plus tard si besoin.
