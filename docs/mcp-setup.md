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

1. Ajouter le même serveur MCP (CLI `claude mcp add` ou config projet).
2. Pour les accès **données** (Gmail/Drive) : préférer les tools MCP.
3. Restreindre le shell : ne pas autoriser `gws` nu ni l’édition de
   `~/.config/gws-accounts/` — voir [threat-model.md](threat-model.md).
4. Unlock / grant restent **humains** (`gwsa` ou admin `http://127.0.0.1:4877`).

Exemple :

```bash
claude mcp add google-multi-account --env GWSA_CLIENT=claude-code -- /ABS/PATH/google-mcp-multi-account/bin/google-mcp
```

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

**1 · Déployer une version figée** (une fois, puis à chaque version) :

```bash
git tag v0.2.0 && ./scripts/deploy-local.sh
```

Le script refuse un arbre sale ou un HEAD non taggé. Il copie la version dans
`~/.local/share/google-mcp/v0.2.0/`, bascule le lien `current`, et arrête le
broker pour que le nouveau code soit réellement pris en compte.

**2 · Brancher Claude Desktop sur la copie** (le script te l'affiche à la fin) :

```bash
~/.local/share/google-mcp/current/scripts/install-claude-desktop.sh
```

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
