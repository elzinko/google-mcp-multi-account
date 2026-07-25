---
id: 0023
title: Versionner et déployer le MCP en local, découplé du code source de travail
type: feature
priority: P0
version:
epic:
status: shipped
ready: 2026-07-25
pr: "#25"
created: 2026-07-25
---

## Contexte / Problème

Le serveur MCP en service **exécute le working tree**, en direct. Constaté le
2026-07-25 :

- `bin/google-mcp` résout `REPO` depuis sa propre position, puis `cd "$REPO"` et
  `PYTHONPATH="$REPO"` — le code chargé est celui du clone, dans l'état où il se
  trouve à l'instant de l'invocation.
- La fiche [[0013]] (livrée) fait pointer Claude Desktop sur le **chemin absolu de
  `bin/google-mcp` du clone courant** — c'est le mécanisme, et il est volontaire.
- **Aucun tag git, aucune release**, et `SERVER_VERSION = "0.1.0"` en dur dans
  [`gateway/mcp_server.py:16`](../gateway/mcp_server.py) depuis l'origine.
- **Deux serveurs `bin/google-mcp` tournent** en ce moment, lancés par Claude.app
  depuis le répertoire de travail, plus **un broker** (`-m gateway.broker_server`).

Développer expose donc l'outil en service : un `git checkout`, un fichier à moitié
édité, un import cassé, et Claude Desktop / Claude Code perd son serveur MCP — ou
**exécute du code non validé ayant accès aux vraies données Google** des comptes
connectés. Le rayon d'action d'un bug de développement n'est pas le test.

### Le broker rend le problème non déterministe

Figer le code du serveur MCP **ne suffit pas**. `ensure_broker_running()`
([`gateway/executor.py:52`](../gateway/executor.py)) ne relance pas le broker s'il
répond déjà au ping, et le port est **fixe** (`DEFAULT_PORT = 4878`). Le broker est
démarré avec `cwd=REPO_DIR` et **rien ne l'arrête** : `bin/gwsa` n'expose aucune
commande de pilotage (pas de `broker stop`/`status`).

Conséquence : dès que deux versions coexistent, **le premier broker démarré impose
son code à l'autre** pour toute l'exécution `gws` — policy, verrous, journal
compris. Dans les deux sens :

- la version stable peut se retrouver à exécuter le code de développement ;
- le développement peut sembler valider une modification alors qu'il tourne le code
  de l'ancien broker — faux positif **silencieux**.

Il n'existe par ailleurs aucun moyen de dire « la version que j'utilise » par
opposition à « la version sur laquelle je travaille ».

## Valeur

- **Ferme un risque sur des données réelles** : aujourd'hui, tout code en chantier
  hérite de l'accès Gmail/Drive des comptes connectés. C'est le seul point du projet
  où une erreur de développement a un effet hors du poste.
- **Rend l'outil de travail fiable** : le MCP sert à travailler ; il ne doit pas
  dépendre de l'état du chantier en cours. Sans ça, développer et utiliser le
  produit s'excluent mutuellement.
- **Rend les tests de développement dignes de confiance** : le partage de broker
  fait mentir les essais sans le signaler. Un résultat qui dépend de l'ordre de
  démarrage n'est pas un résultat.
- **Prépare [[0020]] sans le faire** : le versionnement posé ici est ce que le
  packaging distribuable réutilisera.

## Proposition

Arbitrages PO du 2026-07-25 : copie figée versionnée, tag git sémantique, et un
`GWSA_ROOT` dédié au développement.

**1 · Artefact figé.** Un script `scripts/deploy-local.sh` (idempotent, dans le
moule de `provision-gcp.sh` / `install-claude-desktop.sh`) copie l'arbre — hors
`.git/`, `.claude/worktrees/` — vers `~/.local/share/google-mcp/<version>/`, puis
bascule le symlink `~/.local/share/google-mcp/current`. Le rollback est un
repointage de symlink. Le script **refuse** de déployer un arbre sale ou non taggé.

**2 · Version réelle.** Tag git sémantique (`v0.2.0`). `SERVER_VERSION` en découle
au lieu d'être une constante — le serveur annonce dans `initialize` la version
qu'il exécute vraiment.

**3 · Deux couloirs étanches.**

| | Stable (en service) | Dev (le clone) |
|---|---|---|
| Code | `~/.local/share/google-mcp/current/` | le working tree |
| `GWSA_ROOT` | `~/.config/gws-accounts` | `~/.config/gws-accounts-dev` |
| `GWSA_BROKER_PORT` | `4878` (défaut) | `4880` |
| Entrée MCP | `google-multi-account` | `google-multi-account-dev` |

Les deux leviers existent déjà en variables d'environnement — aucune refonte. Les
deux entrées MCP se posent avec l'option `--name` de `install-claude-desktop.sh`,
déjà livrée par [[0013]].

**4 · Pilotage du broker** — le maillon manquant. Sans arrêt possible, un
déploiement laisse l'ancien broker servir l'ancien code indéfiniment. Ajouter au
minimum un **arrêt** et un **statut** du broker, et faire que `deploy-local.sh`
recycle celui de la version stable en fin de déploiement.

## Critères d'acceptation

- [ ] Casser volontairement un import dans le clone ne change **rien** au
      comportement du MCP stable (vérifié en cassant, pas en relisant).
- [ ] `initialize` du serveur stable annonce la **version déployée** (dérivée du
      tag), plus `0.1.0`.
- [ ] `scripts/deploy-local.sh` déploie en un geste, est **idempotent**, et refuse
      un arbre sale ou sans tag (message clair, exit ≠ 0).
- [ ] Après déploiement, le broker qui sert le stable exécute le **code
      fraîchement déployé** — vérifiable par la version annoncée.
- [ ] Stable et dev tournent **simultanément** sans jamais partager de broker
      (ports distincts, vérifié les deux serveurs actifs).
- [ ] `profiles_list` côté **dev** ne renvoie **aucun** compte de
      `~/.config/gws-accounts` (root dédié effectif).
- [ ] Retour à la version précédente en un geste, sans redéployer.
- [ ] Le geste de déploiement reste **humain** (doctrine CLAUDE.md : le LLM guide
      via `next_actions`, il n'exécute pas — le script touche des chemins machine).

## Dépendances externes

Toutes locales, toutes constatées le **2026-07-25** :

- **Config Claude Desktop** — `~/Library/Application Support/Claude/claude_desktop_config.json`
  présente, 3 entrées MCP dont `google-multi-account`. *Accès constaté* (existence
  et clés seules). `install-claude-desktop.sh` sait déjà y fusionner une entrée
  nommée sans toucher aux autres serveurs.
- **`~/.config/gws-accounts`** — présent. *Accès constaté* (existence seule ;
  contenu jamais lu ni affiché, cf. CLAUDE.md §4).
- **`~/.local/share`** — inscriptible. *Accès constaté.*
- **`gws` dans le PATH** — résolu à l'exécution par `shutil.which("gws")` dans le
  broker. **Limite assumée** : figer le code ne fige pas le binaire `gws` ; une
  mise à jour de `googleworkspace-cli` affecte les deux couloirs.

## Hors périmètre

- Packaging distribuable (`.mcpb`, releases publiques) → [[0020]].
- Figer le binaire `gws` lui-même (voir limite ci-dessus).
- **Angle mort à documenter** : `bin/gwsa` appelle `gws` **directement**
  (`exec gws "$@"`), sans passer par le broker. Le CLI n'est donc pas isolé par le
  port broker — seulement par `GWSA_ROOT`. Suffisant ici, mais à écrire noir sur
  blanc pour ne pas croire l'isolation plus forte qu'elle n'est.

## Notes

- **P0 arbitrée par le PO le 2026-07-25** : seule fiche P0, devant l'épic [[0017]]
  et ses enfants.
- **Hors épic 0017** délibérément : hygiène de développement pour l'auteur, pas
  généralisation à des tiers.
- **Frontière avec [[0020]]** : ici le déploiement local de l'auteur ; là-bas la
  distribution à un tiers. Si cette fiche livre le versionnement, 0020 le réutilise.
- [[0013]] n'est pas à rouvrir : son script reste le point d'entrée, c'est sa
  **cible** qui change (artefact déployé au lieu du clone) — et il gère déjà le
  `--name` nécessaire au second couloir.
- Amorcer le root de dev demandera de connecter au moins un compte
  (`gwsa add` sur `GWSA_ROOT=~/.config/gws-accounts-dev`) — geste humain, une fois.

## Livré — PR #25 (rebase-merge le 2026-07-26)

Écarts entre le plan et la réalisation, pour mémoire :

- **Port de développement : 4880, pas 4879.** La suite de tests occupe déjà 4879
  (`scripts/test.sh`, broker Phase 2 A) — les faire cohabiter aurait rendu les
  tests instables dès qu'un couloir de dev tourne.
- **Durcissement non prévu** : `broker stop` vérifie la signature du process avant
  de tuer. Un pidfile périmé pointant un pid recyclé aurait condamné un process
  innocent. Couvert par un test dédié.
- **Cas non prévu** : un broker lancé *avant* cette version n'a pas de pidfile.
  `broker status` teste donc aussi le port et le signale, au lieu d'annoncer « arrêté »
  à tort. Observé en vrai — un broker orphelin tournait sur le port 4899.
- **CI cloud non exécutée** : GitHub Actions refuse de démarrer (facturation).
  Validation faite par la gate locale `act` + Docker (job CI complet en conteneur
  Linux, 112 tests verts) — merge décidé par le PO en connaissance de cause.
- Les critères d'acceptation portant sur l'exécution réelle (couloirs simultanés,
  `profiles_list` du dev vide) restent à constater par l'humain au premier
  déploiement : ils dépendent de gestes machine que le LLM n'exécute pas.
