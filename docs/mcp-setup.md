# Brancher le serveur MCP (Claude Desktop, Cursor, Claude Code)

Le binaire [`bin/google-mcp`](../bin/google-mcp) expose un serveur MCP **stdio**
(JSON-RPC, une ligne = un message). Il ne parle à Google que via la
[gateway](../gateway/) (policy + verrous + executor v1 → `gws`).

Prérequis : `gws` installé, Python 3. (Pas besoin d'avoir déjà connecté un
compte : le tool `setup_status` guide l'initialisation depuis le client LLM.)

Remplace `/ABS/PATH/google-mcp-multi-account` par le chemin absolu du clone.

## Claude Desktop

**Automatique (recommandé)** — le script résout le chemin absolu tout seul,
fusionne l'entrée sans écraser tes autres serveurs MCP, fait un backup :

```bash
./scripts/install-claude-desktop.sh          # branche (ou met à jour)
./scripts/install-claude-desktop.sh --print  # dry-run : montre sans écrire
```

Idempotent (relançable sans risque). Puis **redémarrer Claude Desktop**.

**À la main** — éditer `~/Library/Application Support/Claude/claude_desktop_config.json` :

```json
{
  "mcpServers": {
    "google-multi-account": {
      "command": "/ABS/PATH/google-mcp-multi-account/bin/google-mcp",
      "env": {
        "GWSA_CLIENT": "claude-desktop"
      }
    }
  }
}
```

Tools attendus (après redémarrage) : `profiles_list`, `setup_status`,
`gmail_list`, `gmail_get`, `gmail_draft_create`, `drive_list`, `drive_get`,
`drive_create`, `access_request`.

## Cursor

Dans les settings MCP (UI ou `~/.cursor/mcp.json`) :

```json
{
  "mcpServers": {
    "google-multi-account": {
      "command": "/ABS/PATH/google-mcp-multi-account/bin/google-mcp",
      "env": {
        "GWSA_CLIENT": "cursor"
      }
    }
  }
}
```

## Claude Code

**Claude Code a sa propre config MCP** (`~/.claude.json`), séparée de Claude
Desktop : brancher Desktop ne le rend **pas** visible dans le CLI `claude`. Il
faut l'enregistrer à part.

Le plus simple — le script dédié, idempotent, qui délègue au CLI officiel :

```bash
./scripts/install-claude-code.sh          # branche au scope user (visible partout)
./scripts/install-claude-code.sh --print  # dry-run : montre la commande
```

`./scripts/update.sh` l'appelle **automatiquement** quand le CLI `claude` est
présent — tu n'as donc en général rien à faire de plus. Sous le capot, c'est :

```bash
claude mcp add google-multi-account --scope user --env GWSA_CLIENT=claude-code --env GWSA_BROKER_PORT=4878 -- ~/.local/share/google-mcp/current/bin/google-mcp
```

`--scope user` le rend visible depuis n'importe quel dossier ; `GWSA_CLIENT=claude-code`
distingue ce client dans le journal ; le port 4878 partage le broker (et donc les
comptes) avec Desktop. Vérifier : `claude mcp get google-multi-account`, ou `/mcp`
dans un nouveau `claude`.

Ensuite, mêmes règles que partout :
- Accès **données** (Gmail/Drive) : préférer les tools MCP.
- Restreindre le shell : ne pas autoriser `gws` nu ni l’édition de
  `~/.config/gws-accounts/` — voir [threat-model.md](threat-model.md).
- Unlock / grant restent **humains** (`gwsa` ou admin `http://127.0.0.1:4877`).

## Les tools exposés, par groupe

| Groupe | Tool | Ce que ça fait |
|---|---|---|
| Découverte | `profiles_list` | Liste les profils (alias, email, verrou, policy) — toujours commencer là |
| Diagnostic | `setup_status` | État du setup (projet, publication, IAM par compte) + `next_actions` : commandes à proposer pour compléter/réparer (lecture seule). Guide l'onboarding, même sans shell (Desktop) |
| Gmail — lecture | `gmail_list` · `gmail_get` | Recherche puis lit les messages d'un compte |
| Gmail — brouillon | `gmail_draft_create` | Prépare un brouillon ; **aucun tool n'envoie de mail** |
| Drive — lecture | `drive_list` · `drive_get` | Liste / inspecte fichiers et dossiers (`webViewLink` compris) et **qui les possède** (`owner`, `owned_by_me`) |
| Drive — écriture zonée | `drive_create` | Crée un fichier sous un parent autorisé (policy zones + grants), **avec son contenu** si `content` est fourni : le markdown devient un Google Doc rédigé ([ADR-0003](adr/ADR-0003-contenu-drive-via-depot-broker.md)) |
| Élicitation | `access_request` | kind=`unlock` \| `grant` \| `add_account` : renvoie **la commande à faire exécuter par l'humain** — n'exécute jamais rien |

Chaque appel traverse la gateway (verrou + policy default-deny) puis le
broker loopback, et tout est journalisé (`GWSA_CLIENT`). Un refus n'est
jamais une impasse : il embarque l'élicitation à proposer — voir les
[diagrammes de séquence](../diagrams/) (lecture, connexion de compte,
réparation IAM).

## Smoke test manuel (sans client)

```bash
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  | ./bin/google-mcp
```

## Développer sans casser le MCP que tu utilises

Par défaut, le serveur branché dans Claude Desktop exécute **le clone**, en direct.
Modifier le code change donc l'outil pendant que tu t'en sers — et du code non
validé garde l'accès aux vrais comptes. Pour séparer les deux :

**1 · Publier une version** — le numéro se calcule tout seul :

```bash
./scripts/release.sh
```

Le niveau vient des conventional commits depuis le dernier tag : un `feat` →
minor, un `BREAKING CHANGE` (ou `type!:`) → major, sinon patch. Passe
`patch`, `minor` ou `major` pour forcer, `--print` pour voir sans rien écrire.

Le script refuse de publier dans le flou : arbre sale, branche autre que
`main`, retard sur `origin/main`, tag déjà posé, aucun commit depuis la
dernière version, ou tests rouges. Au vert il écrit `CHANGELOG.md`, commite,
pose un tag annoté et pousse les deux.

**2 · Installer cette version sur ce poste** — une commande, comme un produit :

```bash
./scripts/update.sh
```

Elle prend la dernière version publiée, l'installe à côté de l'ancienne dans
`~/.local/share/google-mcp/<tag>/`, bascule `current`, recycle le broker, et
ne touche à la config de Claude Desktop que si l'entrée manque ou pointe
ailleurs. Relancée sans rien de neuf, elle dit « déjà à jour » et s'arrête.

| Option | Effet |
|---|---|
| `--check` | dit installé / disponible, n'écrit rien |
| `--to v0.1.0` | installe une version précise (retour arrière) |
| `--force` | réinstalle même si c'est déjà la version courante |

Il reste un geste manuel, incompressible : **redémarrer Claude Desktop**. Le
serveur MCP est lancé par l'application, il ne se recharge pas tout seul.

Les deux commandes sont aussi des verbes de `gwsa`, qui est dans ton PATH :
`gwsa update` et `gwsa release`. Depuis la copie installée, `gwsa release`
retrouve le clone source tout seul (fichier `.source`).

Pour un cas particulier, les briques restent accessibles :
`deploy-local.sh --tag v0.1.0` installe une version sans passer par `update`,
et `install-claude-desktop.sh` branche une entrée à la main.

**3 · Travailler dans le clone**, sur son propre couloir :

| | Stable (en service) | Développement |
|---|---|---|
| Code | `~/.local/share/google-mcp/current/` | ton clone |
| `GWSA_ROOT` | `~/.config/gws-accounts` | `~/.config/gws-accounts-dev` |
| `GWSA_BROKER_PORT` | `4878` (défaut) | `4880` |

```bash
export GWSA_ROOT="$HOME/.config/gws-accounts-dev" GWSA_BROKER_PORT=4880
```

(4879 est réservé à la suite de tests — d'où 4880 pour le développement.)

**Le port distinct n'est pas cosmétique** : le broker ne se relance pas s'il en
existe déjà un qui répond. Sans ports séparés, le premier démarré exécute *tout*,
pour les deux couloirs — tu croirais tester tes modifications alors que tu
exécutes l'ancien code.

Vérifier qui est qui : le serveur annonce sa version dans `initialize`. La copie
déployée annonce son tag, le clone annonce `dev`.

```bash
./scripts/deploy-local.sh --list        # versions déployées (* = courante)
./scripts/deploy-local.sh --rollback v0.1.0
gwsa broker status                      # sur le couloir courant
```

`gwsa broker status|stop` ne pilote que le broker de **son** port : le pidfile
s'appelle `.broker-<port>.pid`, le jeton `.broker-<port>-token`.

## Brancher deux versions en même temps

Utile pour essayer une version sans perdre celle qui marche. Chaque entrée a
besoin de son propre nom **et** de son propre port :

```bash
~/.local/share/google-mcp/v0.1.0/scripts/install-claude-desktop.sh \
  --name google-multi-account-v0.1.0 --port 4881
```

Trois règles, sinon le nom de l'entrée ment sur la version qui répond :

- **Un port par entrée.** L'installeur écrit `GWSA_BROKER_PORT` dans la config,
  et refuse deux binaires différents sur un même port.
- **Viser le dossier de version, jamais `current`.** `current` suit le symlink :
  une entrée épinglée dessus changerait au déploiement suivant.
- **Garder le même `GWSA_ROOT`.** Les comptes sont partagés : pas de
  reconnexion pour essayer une version.

Rappel : le serveur MCP et le broker sont deux process. Le serveur construit les
commandes, le broker les exécute et applique verrous, policy et zones. Deux
versions sur un même port se partagent le premier broker démarré — le résultat
ne correspond alors à aucune des deux.

Le couloir de développement part avec un `GWSA_ROOT` vide : il faut y connecter au
moins un compte (`gwsa add <alias>`) — geste humain, une fois. C'est le prix de
l'isolation : ton code en chantier ne voit pas tes vrais comptes.

## Limites v1

- Pas d’outil d’envoi Gmail (brouillons seulement).
- Pas de Calendar/Docs/Sheets en tools MCP (même gateway, plus tard).
- Pas de broker de tokens : un shell libre peut encore contourner — mitigations
  dans [threat-model.md](threat-model.md).
