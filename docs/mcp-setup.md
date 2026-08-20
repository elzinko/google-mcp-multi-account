# Installer & mettre à jour le serveur MCP

Le binaire [`bin/google-mcp`](https://github.com/elzinko/google-mcp-multi-account/blob/main/bin/google-mcp) expose un serveur MCP **stdio**
(JSON-RPC, une ligne = un message). Il ne parle à Google que via la
[gateway](https://github.com/elzinko/google-mcp-multi-account/tree/main/gateway/) (policy + verrous + executor v1 → `gws`).

Prérequis : la CLI [`gws`](https://github.com/googleworkspace/cli) installée
(`brew install googleworkspace-cli`) et Python 3. (Pas besoin d'avoir déjà connecté
un compte : le tool `setup_status` guide l'initialisation depuis le client LLM.)

## Installer sans cloner (curl)

Pour **utiliser** le serveur (pas le développer), pas besoin de cloner le dépôt :

```bash
curl -fsSL https://raw.githubusercontent.com/elzinko/google-mcp-multi-account/main/install.sh | bash
```

Ça télécharge la dernière version publiée, la fige dans
`~/.local/share/google-mcp/` et met `mag` sur le PATH. **Aucun client LLM n'est
branché par défaut** : l'install imprime le geste (`mag wire …`, voir [plus bas](#brancher-un-client-llm)) ;
ajoute `--wire` (ou `GWSA_WIRE=1`) pour brancher pendant l'install.
Reste le setup Google (OAuth/GCP), un **préalable** affiché à la fin — voir
[Prérequis — OAuth / Google Cloud](setup-oauth.md).

Mettre à jour plus tard, **toujours sans clone** :

```bash
mag update            # dernière version publiée · --to v0.1.0 pour un retour arrière
```

`mag update` lit la dernière version sur GitHub et bascule `current` dessus. Le
clone git n'est nécessaire que pour **contribuer** (fiche 0020).

## Brancher un client LLM

Une fois installé, relie ton assistant en une commande :

```bash
mag wire desktop      # Claude Desktop
mag wire code         # Claude Code (le CLI « claude »)
mag wire all          # les deux — « --print » pour un dry-run
```

Détail par client (Claude Desktop, Claude Code, **Cursor**), config manuelle et
retrait d'une entrée → **[Configurer un client LLM](configurer-client.md)**.

## Les tools exposés, par groupe

| Groupe | Tool | Ce que ça fait |
|---|---|---|
| Découverte | `profiles_list` | Liste les profils (alias, email, verrou, policy) — toujours commencer là |
| Diagnostic | `setup_status` | État du setup (projet, publication, IAM par compte) + `next_actions` : commandes à proposer pour compléter/réparer (lecture seule). Guide l'onboarding, même sans shell (Desktop) |
| Gmail — lecture | `gmail_list` · `gmail_get` | Recherche puis lit les messages d'un compte |
| Gmail — pièce jointe | `gmail_attachment_get` | Télécharge une PJ dans le répertoire local dédié `.downloads` — jamais un chemin arbitraire, jamais d'écrasement ([ADR-0006](adr/ADR-0006-fichiers-recus-repertoire-dedie.md)) |
| Gmail — brouillon | `gmail_draft_create` | Prépare un brouillon ; **aucun tool n'envoie de mail** |
| Drive — lecture | `drive_list` · `drive_get` · `drive_read` | Liste / inspecte fichiers et dossiers (`webViewLink` compris) et **qui les possède** (`owner`, `owned_by_me`) ; `drive_read` lit le **contenu** en texte (Doc → markdown, Sheet → CSV, fichiers texte tels quels — pas les binaires) |
| Drive — écriture zonée | `drive_create` · `drive_update` · `drive_copy` · `drive_upload` | Sous un parent autorisé (policy zones + grants) : crée / **modifie**, **copie** nativement, ou **téléverse** un fichier local ([ADR-0003](adr/ADR-0003-contenu-drive-via-depot-broker.md)) |
| Drive — partage | `drive_permissions_list` · `drive_permissions_create` · `drive_permissions_delete` | Liste, accorde (reader/commenter/writer) ou révoque des partages (policy `share:true` requise) ; **transfert de propriété hors périmètre** (PR dédiée non prête) |
| Élicitation | `access_request` | kind=`unlock` \| `grant` \| `add_account` : renvoie **la commande à faire exécuter par l'humain** — n'exécute jamais rien |

**Policy admin ≠ surface MCP.** Cocher une case dans l'admin autorise les
méthodes API correspondantes via `mag` ; le MCP en expose un sous-ensemble.
Depuis les fiches [0043](https://github.com/elzinko/google-mcp-multi-account/blob/main/features/0043-lire-copier-televerser-drive-et-pj-gmail.md)
et ce lot (update + partage), lecture de contenu, copie, téléversement,
modification et partage y sont. Le **transfert de propriété** est hors périmètre
(PR dédiée non prête). Calendar / Keep peuvent encore figurer dans la policy sans
tool MCP (élargissement : fiche
[0021](https://github.com/elzinko/google-mcp-multi-account/blob/main/features/0021-couverture-mcp-elargie.md)). Et par design, **aucun
tool** n'envoie de mail, ne supprime, ni ne transfère de propriété.

Chaque appel traverse la gateway (verrou + policy default-deny) puis le
broker loopback, et tout est journalisé (`GWSA_CLIENT`). Un refus n'est
jamais une impasse : il embarque l'élicitation à proposer — voir les
[diagrammes de séquence](https://github.com/elzinko/google-mcp-multi-account/tree/main/diagrams/) (lecture, connexion de compte,
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

Les deux commandes sont aussi des verbes de `mag`, qui est dans ton PATH :
`mag update` et `mag release`. Depuis la copie installée, `mag release`
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
mag broker status                      # sur le couloir courant
```

`mag broker status|stop` ne pilote que le broker de **son** port : le pidfile
s'appelle `.broker-<port>.pid`, le jeton `.broker-<port>-token`.

## Brancher deux versions en même temps

Utile pour essayer une version sans perdre celle qui marche. Chaque entrée a
besoin de son propre nom **et** de son propre port :

```bash
~/.local/share/google-mcp/v0.1.0/scripts/install-claude-desktop.sh \
  --name google-multi-account-v0.1.0 --port 4881
```

Pour une **branche / PR jetable** (sans toucher `current` ni l'entrée stable
`google-multi-account` @ 4878) : `mag sandbox deploy --wire` (ou
`mag sandbox wire` après coup). Unwire sélectif :
`mag sandbox wire --remove desktop` (répertoire conservé) ;
nucléaire : `mag sandbox remove <id>`. Détail : `mag sandbox --help` et fiche
[0046](https://github.com/elzinko/google-mcp-multi-account/blob/main/features/0046-sandbox-deploy-cli.md).

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

Le couloir de développement part sans comptes : `mag dev deploy --isolated`
crée `~/.config/gws-accounts-dev` et y copie `client_secret.json` depuis la
prod (l'app OAuth seulement — pas les tokens). Il reste à connecter au moins
un compte de test (`GWSA_ROOT=… mag add <alias>`) — geste humain, une fois.
C'est le prix de l'isolation : ton code en chantier ne voit pas tes vrais
comptes.

Pour valider une PR depuis un worktree : `./bin/mag dev test` déploie la
branche courante, redémarre l'admin sur le code déployé et affiche un résumé
(id, URL, marqueur `afSearchHits`). Voir [PR_VALIDATION.md](PR_VALIDATION.md).

## Limites v1

- Pas d’outil d’envoi Gmail (brouillons seulement).
- Pas de Calendar/Docs/Sheets en tools MCP (même gateway, plus tard).
- Pas de broker de tokens : un shell libre peut encore contourner — mitigations
  dans [threat-model.md](threat-model.md).
