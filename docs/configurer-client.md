# Brancher un client LLM

Une fois le serveur [installé](mcp-setup.md), une **seule commande** le relie à ton
assistant, depuis n'importe où (`gma` est sur le PATH) :

```bash
gma wire desktop      # Claude Desktop
gma wire code         # Claude Code (le CLI « claude »)
gma wire all          # les deux — « --print » pour un dry-run
```

`gma wire` résout le chemin absolu, **fusionne** l'entrée `google-multi-account` sans
écraser tes autres serveurs MCP, et fait un backup. Puis **redémarre le client**.

!!! note "Pourquoi deux noms ?"
    Le **dépôt** s'appelle `google-mcp-multi-account`, mais le **connecteur** déclaré
    sous `mcpServers` s'appelle `google-multi-account` (sans `mcp`) — convention MCP,
    comme `github-mcp-server` → `github`. Détail :
    [architecture](architecture.md#noms-depot-connecteur).

## Détail par client

=== "Claude Desktop"

    **Recommandé** — une commande :

    ```bash
    gma wire desktop           # branche (ou met à jour)
    gma wire desktop --print   # dry-run : montre sans écrire
    ```

    **À la main** — éditer `~/Library/Application Support/Claude/claude_desktop_config.json` :

    ```json
    {
      "mcpServers": {
        "google-multi-account": {
          "command": "/ABS/PATH/google-mcp-multi-account/bin/google-mcp",
          "env": { "GWSA_CLIENT": "claude-desktop" }
        }
      }
    }
    ```

    Puis **redémarrer Claude Desktop**.

=== "Claude Code"

    **Claude Code a sa propre config MCP** (`~/.claude.json`), séparée de Claude
    Desktop : brancher Desktop ne le rend **pas** visible dans le CLI `claude`.

    **Recommandé** :

    ```bash
    gma wire code
    ```

    Sous le capot, ça délègue au CLI officiel (scope `user` = visible partout) :

    ```bash
    claude mcp add google-multi-account --scope user \
      --env GWSA_CLIENT=claude-code --env GWSA_BROKER_PORT=4878 \
      -- ~/.local/share/google-mcp/current/bin/google-mcp
    ```

    Vérifier : `claude mcp get google-multi-account`, ou `/mcp` dans un nouveau `claude`.

=== "Cursor"

    Pas encore de `gma wire cursor` (suivi : fiche 0074). Config manuelle courte —
    dans les settings MCP (UI ou `~/.cursor/mcp.json`) :

    ```json
    {
      "mcpServers": {
        "google-multi-account": {
          "command": "/ABS/PATH/google-mcp-multi-account/bin/google-mcp",
          "env": { "GWSA_CLIENT": "cursor" }
        }
      }
    }
    ```

## Retirer une entrée

- **Claude Code** : `claude mcp remove google-multi-account`.
- **Desktop / Cursor** : retirer l'entrée `google-multi-account` du JSON de config du
  client (l'admin protège volontairement l'entrée stable — pas de suppression par mégarde).

!!! info "Sous le capot"
    `gma wire` appelle `scripts/install-claude-desktop.sh` / `install-claude-code.sh`
    (idempotents, avec backup). Tu n'as normalement pas à les lancer à la main — ils
    restent là pour les cas particuliers (nom/port personnalisés, plusieurs versions :
    voir [Installer & mettre à jour](mcp-setup.md)).
