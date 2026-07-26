---
id: 0025
title: Couloirs étanches — chaque version branchée parle à son propre broker
type: bug
priority: P1
version:
epic:
status: in-progress
ready: 2026-07-26
pr: "#27"
created: 2026-07-26
---

## Contexte / Problème

Le MCP tourne en **deux process** : le serveur MCP (lancé par le client) et le
broker (service de fond, seul à exécuter `gws`). Le serveur ne connaît pas
« son » broker : il parle à celui qui écoute sur `GWSA_BROKER_PORT`, 4878 par
défaut.

Aujourd'hui, `install-claude-desktop.sh` écrit une entrée sans port :

```json
"google-multi-account": {"command": "…/bin/google-mcp",
                         "env": {"GWSA_CLIENT": "claude-desktop"}}
```

Donc **toutes** les entrées, quel que soit leur nom, visent le port 4878. Le
premier broker démarré sert tout le monde. Brancher deux versions côte à côte
(`…-v0.1.0` et `…-dev`) produit un mélange, pas un choix :

| Ce qui vient du serveur MCP | Ce qui vient du broker |
|---|---|
| `gateway/api.py` — construction des commandes gws | `broker_server.py` — exécution de `gws` |
| les tools exposés, leurs schémas | `scripts/policy-check.py` — verrous, policy, zones |

Le symptôme est déjà connu : un `api.py` v0.1.0 (fiche 0024, ADR-0003) qui
dépose son média dans `<GWSA_ROOT>/.uploads` face à un broker d'avant, qui
lance `gws` depuis le dépôt git → `--upload … outside the current directory`.
Deux entrées correctement nommées, un comportement qui n'est celui d'aucune
des deux.

Second défaut, qui bloque la sortie de secours : les fichiers de suivi du
broker (`.broker-token`, `.broker.pid`) ne sont indexés que par `GWSA_ROOT`.
Deux brokers sur deux ports, même racine → le second écrase le pidfile du
premier, et `gwsa broker stop` arrête le mauvais process.

## Proposition

Faire du **port une propriété du couloir**, écrite noir sur blanc.

1. `install-claude-desktop.sh --port <n>` : le port part dans le bloc `env` de
   l'entrée. Il est écrit même pour 4878, pour que le couloir soit lisible
   dans la config.
2. Le script **refuse** d'écrire une entrée si un autre serveur `google-mcp`
   de la config occupe déjà ce port avec un binaire différent — c'est le
   garde-fou qui empêche le mélange silencieux.
3. Le script affiche la version qu'il branche (fichier `VERSION` à côté du
   binaire, sinon `dev`), pour qu'on voie ce qu'on fait.
4. `.broker-<port>.pid` et `.broker-<port>-token` : les fichiers de suivi
   deviennent propres à un port. `bin/gwsa broker status|stop` suit.

Les comptes (`GWSA_ROOT`) restent **partagés** entre le couloir stable et un
couloir épinglé : on ne veut pas reconnecter cinq comptes pour tester une
version.

## Critères d'acceptation

- [x] `--port 4881` écrit `GWSA_BROKER_PORT: "4881"` dans l'entrée ; sans
      l'option, `4878` est écrit explicitement.
- [x] Deux entrées, deux binaires, même port → **refus** avec le message qui
      dit quoi faire (`--port`). Même binaire + même port → idempotent.
- [x] Un serveur MCP tiers (autre `command`) n'est jamais compté comme un
      concurrent de port.
- [x] Le script affiche la version branchée (`v0.1.0` ou `dev`).
- [x] Deux brokers sur deux ports ont deux pidfiles et deux jetons distincts ;
      arrêter l'un laisse l'autre en vie.
- [x] `gwsa broker status|stop` pilote le broker du port courant
      (`GWSA_BROKER_PORT`), pas celui du voisin.
- [x] Un broker lancé avant cette version (pidfile historique) reste signalé
      comme « écoute sans pidfile », jamais annoncé « arrêté ».
- [x] `./scripts/test.sh` vert.

## Notes

- Découle de la mise en service du couloir stable (fiche 0023, tag `v0.1.0`
  déployé le 2026-07-26) : tant qu'une seule version tournait, le port partagé
  ne se voyait pas.
- Le nommage des entrées (`google-multi-account-v0.1.0`) existe déjà via
  `--name`. C'est le port qui manquait pour que ce nom dise la vérité.
- Une entrée épinglée doit viser `~/.local/share/google-mcp/<tag>/bin/google-mcp`
  et **jamais** `current/`, qui suit le symlink et change au déploiement suivant.
