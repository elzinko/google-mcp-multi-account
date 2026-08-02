# google-multi-account

**Google Workspace multi-comptes pour agents LLM — 100 % local.**

Branche Claude Desktop, Claude Code ou Cursor sur *plusieurs* comptes Google via
un serveur [MCP](https://modelcontextprotocol.io) local. L'agent peut *demander*
un accès ; c'est toi seul qui l'accordes — chaque déverrouillage, chaque zone
Drive, chaque nouveau compte reste un **geste humain**.

<div class="grid cards" markdown>

- :material-rocket-launch: **[Démarrer en 3 minutes](#installer-en-3-minutes)**
  Installer sans cloner, connecter un compte, poser la question au LLM.

- :material-shield-lock: **[Sécurité d'abord](threat-model.md)**
  Default-deny, verrous par profil, écritures Drive zonées, zéro envoi de mail.

- :material-tools: **[CLI & admin](usage.md)**
  `gwsa` : profils, verrous, zones Drive, Touch ID, interface web locale.

- :material-sitemap: **[Sous le capot](architecture.md)**
  MCP, gateway, broker loopback, wrapper — qui parle à qui.

</div>

## Ce que tu obtiens

- **Multi-comptes, pas un seul token** — chaque compte est un *profil* avec sa
  policy, ses verrous et ses zones Drive. L'agent vise un alias, jamais « ton
  Google » en bloc.
- **L'humain tient chaque porte** — déverrouillage, zone Drive, nouveau compte,
  correctif IAM : l'agent *propose la commande exacte* (élicitation), tu l'exécutes.
- **Default-deny par conception** — tout service non déclaré est refusé ; les
  tools Gmail s'arrêtent au brouillon (aucun envoi) ; les écritures Drive restent
  dans les dossiers accordés.
- **100 % local** — tokens chiffrés (AES-256-GCM, clé maître dans le Keychain
  macOS), journal d'audit par client. Seule étape cloud : un credential OAuth,
  une fois.

## Installer en 3 minutes

Pour **utiliser** le serveur, pas besoin de cloner le dépôt :

```bash
curl -fsSL https://raw.githubusercontent.com/elzinko/google-mcp-multi-account/main/install.sh | bash
```

Ça télécharge la dernière version, la met sur ton poste, branche tes clients, et
affiche à la fin le **setup Google** restant (voir [OAuth / Google Cloud](setup-oauth.md)).

Connecter un compte, puis redémarrer Claude Desktop :

```bash
gwsa add perso        # navigateur → choisir le compte → accepter
gwsa list             # profils + état
```

Mettre à jour plus tard, **toujours sans clone** :

```bash
gwsa update
```

!!! tip "Cloner, c'est pour contribuer"
    Le clone git n'est nécessaire que pour développer le projet. Voir
    [Installer & mettre à jour](mcp-setup.md) et [Contribuer](PR_VALIDATION.md).

## Aller plus loin

| Je veux… | Page |
|---|---|
| Brancher un client, connaître les tools exposés | [Installer & mettre à jour](mcp-setup.md) |
| Faire le setup OAuth / Google Cloud, les rôles IAM | [OAuth / Google Cloud](setup-oauth.md) |
| Piloter `gwsa` (profils, verrous, zones, admin) | [CLI & admin](usage.md) |
| Comprendre le modèle de policy (default-deny, zones) | [Modèle de policy](policies.md) |
| Voir les garanties de sécurité, phase par phase | [Modèle de menace](threat-model.md) |
| Un regard honnête (forces, limites, concurrence) | [Critique](critique.md) |

---

Projet open-source ([MIT](https://github.com/elzinko/google-mcp-multi-account/blob/main/LICENSE)),
construit sur le temps libre. Un souci de sécurité ?
[SECURITY.md](https://github.com/elzinko/google-mcp-multi-account/blob/main/SECURITY.md).
