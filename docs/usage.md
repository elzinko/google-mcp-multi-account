# Utilisation au quotidien

Détails d'usage de `mag`, du verrou « accès sur demande » et de
l'authentification forte. Interface d'admin web (page séparée) :
[admin.md](admin.md). Vue d'ensemble : [README](https://github.com/elzinko/google-mcp-multi-account/blob/main/README.md).
Modèle de policy (qui a le droit de quoi) : [policies.md](policies.md).

## En ligne de commande (`mag`)

**Aide en ligne** : `mag help` (liste les sous-commandes) ; `mag
<sous-commande> --help` pour le détail.

Le wrapper isole chaque compte via `GOOGLE_WORKSPACE_CLI_CONFIG_DIR`. On désigne
un compte par son **adresse email** (le plus clair) et on appelle
`mag <email> <commande gws…>` (jamais `gws` nu) :

```bash
mag vous@gmail.com gmail users messages list --params '{"userId":"me","maxResults":5}'
mag vous@gmail.com drive files list --params '{"pageSize":10}'
mag vous@gmail.com calendar +agenda --today    # agenda du jour
mag vous@gmail.com auth status                 # état du token
```

> **Alias = raccourci optionnel.** Si l'email est long à taper, nomme le compte
> à la connexion (`mag add perso vous@gmail.com`) puis utilise l'alias court
> (`mag perso …`) partout où un email est accepté.

Pour les données (Gmail/Drive), préférer les **tools MCP** (voir
[mcp-setup.md](mcp-setup.md)). Le shell `mag` reste pour l'admin humain et
les cas non couverts par le MCP.

## Connexion sur demande (élicitation)

Un profil peut être **verrouillé** : il reste connecté (token en place) mais
refuse toute commande tant que tu ne l'as pas déverrouillé explicitement —
le LLM qui se heurte au verrou doit te le demander.

```bash
mag lock vous@gmail.com        # accès sur demande uniquement
mag vous@gmail.com gmail …     # ✗ profil verrouillé 🔒 → le LLM doit demander
mag unlock vous@gmail.com 30   # déverrouillé 30 min, reverrouillage automatique
```

[.claude/settings.json](https://github.com/elzinko/google-mcp-multi-account/blob/main/.claude/settings.json) ajoute une seconde barrière,
native Claude Code : les commandes sur les profils sensibles (et `mag unlock`)
déclenchent une demande de permission explicite.

Séquence illustrée : [diagrams/lecture-donnees-elicitee](https://github.com/elzinko/google-mcp-multi-account/tree/main/diagrams/lecture-donnees-elicitee/).

## Authentification forte (Touch ID) — optionnelle

```bash
mag strongauth on      # unlock et grant exigeront Touch ID / Apple Watch
mag strongauth status  #   (ou mot de passe de session macOS en secours)
mag strongauth off     # désactivation (elle-même protégée par Touch ID)
```

Une fois activée, chaque déverrouillage de profil et chaque autorisation de
zone Drive déclenche la boîte de dialogue biométrique système
([scripts/touchid.swift](https://github.com/elzinko/google-mcp-multi-account/blob/main/scripts/touchid.swift), framework LocalAuthentication
d'Apple, 100 % local). L'approbation d'élicitation ne peut alors plus venir
que d'un humain physiquement présent devant le Mac — un LLM (ou un script)
ne peut pas la simuler. Elle s'applique aussi à `mag add` (connexion d'un
nouveau compte).

## Depuis Claude Code

Ouvrir une session dans ce repo : les skills `.claude/skills/gws-*` et les
consignes [CLAUDE.md](https://github.com/elzinko/google-mcp-multi-account/blob/main/CLAUDE.md) sont chargés automatiquement. Demander en
langage naturel, par ex. « liste mes 5 derniers mails du compte perso ».
