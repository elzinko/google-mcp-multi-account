# Brancher le serveur MCP (Claude Desktop, Cursor, Claude Code)

Le binaire [`bin/google-mcp`](../bin/google-mcp) expose un serveur MCP **stdio**
(JSON-RPC, une ligne = un message). Il ne parle à Google que via la
[gateway](../gateway/) (policy + verrous + executor v1 → `gws`).

Prérequis : `gws` installé, au moins un profil (`gwsa add …`), Python 3.

Remplace `/ABS/PATH/google-mcp-multi-account` par le chemin absolu du clone.

## Claude Desktop

Fichier de config (macOS) :
`~/Library/Application Support/Claude/claude_desktop_config.json`

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

Redémarrer Claude Desktop. Tools attendus : `profiles_list`, `gmail_list`,
`gmail_get`, `gmail_draft_create`, `drive_list`, `drive_get`, `drive_create`,
`access_request`.

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
claude mcp add google-multi-account -- /ABS/PATH/google-mcp-multi-account/bin/google-mcp
```

## Les tools exposés, par groupe

| Groupe | Tool | Ce que ça fait |
|---|---|---|
| Découverte | `profiles_list` | Liste les profils (alias, email, verrou, policy) — toujours commencer là |
| Gmail — lecture | `gmail_list` · `gmail_get` | Recherche puis lit les messages d'un compte |
| Gmail — brouillon | `gmail_draft_create` | Prépare un brouillon ; **aucun tool n'envoie de mail** |
| Drive — lecture | `drive_list` · `drive_get` | Liste / inspecte fichiers et dossiers (`webViewLink` compris) |
| Drive — écriture zonée | `drive_create` | Crée un fichier sous un parent autorisé (policy zones + grants) |
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

## Limites v1

- Pas d’outil d’envoi Gmail (brouillons seulement).
- Pas de Calendar/Docs/Sheets en tools MCP (même gateway, plus tard).
- Pas de broker de tokens : un shell libre peut encore contourner — mitigations
  dans [threat-model.md](threat-model.md).
