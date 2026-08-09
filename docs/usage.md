# Utilisation au quotidien

Détails d'usage de `gma`, du verrou « accès sur demande », de l'interface
d'admin et de l'authentification forte. Vue d'ensemble : [README](https://github.com/elzinko/google-mcp-multi-account/blob/main/README.md).
Modèle de policy (qui a le droit de quoi) : [policies.md](policies.md).

## En ligne de commande (`gma`)

Le wrapper isole chaque compte via `GOOGLE_WORKSPACE_CLI_CONFIG_DIR`. On désigne
un compte par son **adresse email** (le plus clair) et on appelle
`gma <email> <commande gws…>` (jamais `gws` nu) :

```bash
gma vous@gmail.com gmail users messages list --params '{"userId":"me","maxResults":5}'
gma vous@gmail.com drive files list --params '{"pageSize":10}'
gma vous@gmail.com calendar +agenda --today    # agenda du jour
gma vous@gmail.com auth status                 # état du token
```

> **Alias = raccourci optionnel.** Si l'email est long à taper, nomme le compte
> à la connexion (`gma add perso vous@gmail.com`) puis utilise l'alias court
> (`gma perso …`) partout où un email est accepté.

Pour les données (Gmail/Drive), préférer les **tools MCP** (voir
[mcp-setup.md](mcp-setup.md)). Le shell `gma` reste pour l'admin humain et
les cas non couverts par le MCP.

## Connexion sur demande (élicitation)

Un profil peut être **verrouillé** : il reste connecté (token en place) mais
refuse toute commande tant que tu ne l'as pas déverrouillé explicitement —
le LLM qui se heurte au verrou doit te le demander.

```bash
gma lock vous@gmail.com        # accès sur demande uniquement
gma vous@gmail.com gmail …     # ✗ profil verrouillé 🔒 → le LLM doit demander
gma unlock vous@gmail.com 30   # déverrouillé 30 min, reverrouillage automatique
```

[.claude/settings.json](https://github.com/elzinko/google-mcp-multi-account/blob/main/.claude/settings.json) ajoute une seconde barrière,
native Claude Code : les commandes sur les profils sensibles (et `gma unlock`)
déclenchent une demande de permission explicite.

Séquence illustrée : [diagrams/lecture-donnees-elicitee](https://github.com/elzinko/google-mcp-multi-account/tree/main/diagrams/lecture-donnees-elicitee/).

## Interface d'admin web

```bash
gma admin                 # démarre (détaché, idempotent) + ouvre http://127.0.0.1:4877
gma admin stop            # arrête ; logs dans ~/.config/gws-accounts/admin.log
```

*(équivalent manuel : `node admin/server.js` — local uniquement)*. Les
messages d'élicitation du MCP citent la commande : n'importe quel client LLM
sait donc te proposer de la démarrer quand elle est utile.

Tout se pilote depuis le navigateur : **connecter un compte** (alias + email
attendu — l'onglet Google s'ouvre avec le bon compte présélectionné et la
connexion est refusée si tu choisis le mauvais), **verrouiller/déverrouiller**
(minutes ou `off`), **éditer la policy** service par service avec préréglages
(« prudent » : Drive zones, Gmail brouillons sans envoi, Agenda lecture, Keep
lecture + création), **journal des accès** (qui a fait quoi sur quel compte —
les LLM s'identifient via la variable `GWSA_CLIENT`), **doc intégrée** (❓ :
installation, schémas de séquence, tools MCP, setup OAuth) et **gros bouton
Révoquer** (supprime les tokens du poste, accès coupé immédiatement).

Ajout d'un dossier autorisé sans jamais saisir d'ID : **🔍 recherche par nom**
(plusieurs correspondances → liste de choix avec le chemin complet) ou **📂
navigation** dans Mon Drive (Ouvrir/Choisir), puis durée : temporaire (défaut
8 h) ou permanent. *(Pourquoi des IDs en interne ? Les noms de dossiers Drive ne
sont pas uniques et changent au gré des renommages/déplacements ; l'ID est la
seule référence stable. L'interface fait la conversion nom → ID pour toi.)*

Sécurité : serveur lié à 127.0.0.1 seulement, en-tête custom obligatoire
(anti-CSRF), Origin contrôlée, aucune dépendance npm (mermaid vendorisé en
local), actions déléguées à `bin/gma` (`execFile`, jamais de shell).

## Authentification forte (Touch ID) — optionnelle

```bash
gma strongauth on      # unlock et grant exigeront Touch ID / Apple Watch
gma strongauth status  #   (ou mot de passe de session macOS en secours)
gma strongauth off     # désactivation (elle-même protégée par Touch ID)
```

Une fois activée, chaque déverrouillage de profil et chaque autorisation de
zone Drive déclenche la boîte de dialogue biométrique système
([scripts/touchid.swift](https://github.com/elzinko/google-mcp-multi-account/blob/main/scripts/touchid.swift), framework LocalAuthentication
d'Apple, 100 % local). L'approbation d'élicitation ne peut alors plus venir
que d'un humain physiquement présent devant le Mac — un LLM (ou un script)
ne peut pas la simuler. Elle s'applique aussi à `gma add` (connexion d'un
nouveau compte).

## Depuis Claude Code

Ouvrir une session dans ce repo : les skills `.claude/skills/gws-*` et les
consignes [CLAUDE.md](https://github.com/elzinko/google-mcp-multi-account/blob/main/CLAUDE.md) sont chargés automatiquement. Demander en
langage naturel, par ex. « liste mes 5 derniers mails du compte perso ».
