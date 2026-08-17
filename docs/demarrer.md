# Démarrer

Ce guide vous emmène de zéro jusqu'à votre premier échange : *« Claude, résume-moi
mes derniers mails »* — sur **plusieurs** comptes Google, **en local**, sans jamais
laisser l'assistant agir tout seul.

Comptez **~15 minutes**, la plupart pour une étape Google qu'on ne fait qu'une fois.

!!! info "Ce qu'il vous faut"
    - un **Mac** (Apple Silicon) ;
    - un client compatible MCP : **Claude Desktop**, **Claude Code** ou **Cursor** ;
    - un ou plusieurs **comptes Google** (`@gmail.com` ou Workspace).

## En une phrase, ça marche comment ?

Un petit serveur tourne **sur votre machine**. Votre assistant lui parle par le
protocole [MCP](https://modelcontextprotocol.io) ; le serveur, lui, parle à Google.
Entre les deux, une règle simple : **l'assistant peut *demander* un accès, mais c'est
vous qui l'ouvrez.** Rien ne quitte votre poste, aucun mail ne part sans votre geste.

## Étape 0 — Installer l'outil Google (`gws`)

Le projet s'appuie sur la CLI officielle **Google Workspace** (`gws`). Installez-la
d'abord, sinon l'étape « connecter un compte » échouera :

```bash
brew install googleworkspace-cli
```

## Étape 1 — Installer le connecteur

Une commande, sans rien cloner :

```bash
curl -fsSL https://raw.githubusercontent.com/elzinko/google-mcp-multi-account/main/install.sh | bash
```

Vous obtenez la commande **`mag`** dans votre terminal (c'est *votre* poste de
pilotage : connecter des comptes, verrouiller, autoriser) et le serveur prêt à être
branché. L'installeur affiche à la fin ce qu'il reste à faire côté Google.

## Étape 2 — Créer le projet Google (une seule fois)

Google impose deux gestes manuels dans sa console : créer un **identifiant OAuth**
et **publier** l'application. C'est gratuit, rien n'est hébergé — juste une carte
d'identité qui autorise `mag` à se connecter à *vos* comptes.

Le guide détaillé, pas à pas : **[OAuth / Google Cloud](setup-oauth.md)** (~10 min).
À la fin, vous avez un fichier `client_secret.json` en place.

## Étape 3 — Connecter un compte

Chaque compte se connecte par le **navigateur** — vous choisissez le compte, Google
demande votre accord. Aucun mot de passe ne transite par l'outil.

```bash
mag add perso vous@gmail.com     # « perso » = un nom court ; l'email désigne le compte
```

Répétez pour chaque compte (`mag add asso vous@asso.org`, etc.). Vérifiez :

```bash
mag list                          # vos comptes et leur état
```

!!! tip "Email ou alias ?"
    Partout, vous pouvez désigner un compte par son **email** (`mag lock
    vous@gmail.com`) — le plus clair. Le petit alias (`perso`) reste un **raccourci**
    optionnel si l'email est long à taper.

## Étape 4 — Brancher votre client

Une commande relie le serveur à votre assistant :

```bash
mag wire desktop      # Claude Desktop
mag wire code         # Claude Code (le CLI « claude »)
mag wire all          # les deux
```

Puis **redémarrez le client**. (Pour Cursor et le détail par client, voir [Configurer un client LLM](configurer-client.md).)

## Étape 5 — Premier échange

Dans votre assistant, demandez simplement :

> « Fais-moi le point sur ma configuration Google. »

Il lit l'état et vous propose, pour chaque manque, la commande exacte à lancer.
Ensuite, essayez :

> « Résume les 5 derniers mails de vous@gmail.com. »

S'il bute sur un **verrou** 🔒, c'est normal : un compte peut être verrouillé (accès
sur demande). L'assistant vous propose alors la commande — à vous de l'exécuter :

```bash
mag unlock vous@gmail.com 30      # déverrouillé 30 min, reverrouillage automatique
```

C'est tout le principe : **l'assistant propose, vous disposez.**

## Et ensuite ?

- **[Utiliser au quotidien](usage.md)** — la CLI `mag`, l'interface admin, Touch ID.
- **[Modèle de policy](policies.md)** — ce que chaque compte a le droit de faire (par défaut : lecture, brouillons, zéro envoi).
- **[Sécurité](threat-model.md)** — ce que le projet garantit, et ce qu'il ne garantit *pas*.
- Un souci pendant l'install ? **[Configurer un client LLM](configurer-client.md)** (config manuelle par client) et **[Installer & mettre à jour](mcp-setup.md)** (plusieurs versions, dépannage).
