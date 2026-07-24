# Regard critique — forces, limites, risques

Ce document est une **auto-évaluation honnête** du projet, pour un développeur qui
l'évalue ou veut y contribuer. Il dit ce que le projet fait bien, ce qu'il fait
mal, et ce qui pourrait le rendre inutile. Il complète [`SECURITY.md`](../SECURITY.md)
et [`threat-model.md`](threat-model.md) (centrés sécurité) par une vue plus large :
produit, ingénierie, stratégie.

*Écrit le 2026-07-24. Le projet bouge vite : certaines limites ci-dessous sont déjà
en cours de correction sur `main`.*

## En une phrase

Un outil **soigné et honnête**, aujourd'hui taillé pour **un seul utilisateur**
(son auteur, sur macOS). Son argument de sécurité ne tient **pas** face à un agent
qui dispose d'un shell.

## Ce que le projet fait bien

- **Il documente ses propres failles.** Le threat-model décrit les contournements
  au lieu de les cacher — c'est rare pour un projet.
- **La couche policy est réelle et testée.** Le default-deny par service et par
  compte a une suite de tests hermétique, avec des non-régressions sur de vrais
  contournements trouvés en audit.
- **La gouvernance par compte est rare.** Verrous « accès sur demande », grants
  Drive temporaires, élicitation humaine : on ne retrouve cette combinaison chez
  aucun autre serveur MCP connu (voir [Face à la concurrence](#face-à-la-concurrence)).
- **Il est petit et sans dépendance lourde.** ~3 400 lignes, stdlib pure (Python,
  bash, Node), rien à installer via npm ou PyPI.

## Les limites

### 1. La sécurité protège surtout contre un agent *coopératif*

Le but affiché : le LLM ne peut pas dépasser ce qu'on autorise. En pratique, une
seule commande contourne policy, verrous et journal d'un coup :

```bash
GOOGLE_WORKSPACE_CLI_CONFIG_DIR=~/.config/gws-accounts/<alias> gws …
```

Un client **avec shell** (Claude Code, Cursor) peut la taper. La barrière tient
donc tant que l'agent **veut bien** la respecter — ce n'est pas une vraie serrure.
Le projet le documente lui-même dans [`threat-model.md`](threat-model.md).

Deux nuances honnêtes :

- Pour un client **sans shell** (Claude Desktop en MCP stdio), la barrière tient
  bien mieux.
- Le projet a récemment fait passer les accès aux données par un **broker** (la
  gateway n'appelle plus `gws` en direct). C'est une bonne chose, mais ça ne ferme
  pas le contournement ci-dessus : tant que les credentials restent utilisables par
  `gws`, la commande fonctionne. La vraie fermeture — sortir les credentials du
  périmètre de l'agent — est un chantier identifié, **pas encore fait**.

### 2. Tout repose sur un CLI tiers encore jeune (`gws`)

Le multi-comptes vient d'un détail de `gws` : la variable
`GOOGLE_WORKSPACE_CLI_CONFIG_DIR`. Or `gws` est pré-1.0 (« expect breaking
changes »), et sa sortie texte est lue par expressions régulières à plusieurs
endroits. Une simple release peut casser la chaîne. Aucune version n'est épinglée.
Le multi-comptes natif a d'ailleurs été retiré du CLI, puis réclamé par ses
utilisateurs ([issue #293](https://github.com/googleworkspace/cli/issues/293)) :
s'il revient, ce wrapper devient un alias trivial.

### 3. macOS uniquement (pour l'instant)

Trousseau (clé de chiffrement), Touch ID, `stat -f`, `open` : le chemin de
production ne fonctionne que sur macOS Apple Silicon. Le README le signale
désormais (badge macOS), et le symlink d'installation utilise `$(brew --prefix)`
plutôt qu'un chemin codé en dur. Mais le rendre vraiment portable (Linux, Intel)
reste à faire.

### 4. La couverture MCP est étroite

9 outils MCP, dont 3 utilitaires. On a Gmail (lire + brouillon) et Drive (lire +
créer). Calendar, Docs, Sheets, Tasks : **aucun** outil MCP — accessibles seulement
via le shell `gwsa`, donc **pas depuis Claude Desktop**. En face,
[taylorwilsdon/google_workspace_mcp](https://github.com/taylorwilsdon/google_workspace_mcp)
expose une centaine d'outils sur 12 services. C'est le point le plus faible face à
la concurrence.

### 5. L'installation est coûteuse

Chaque utilisateur doit créer sa **propre application OAuth** dans la console Google
Cloud. Les scopes utilisés (Drive complet, `gmail.modify`) sont classés
**restreints** par Google. Conséquence :

- une app partagée doit passer une [vérification des scopes
  restreints](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification)
  et un audit de sécurité **CASA**, à refaire **chaque année** (payant) ;
- sinon, on reste en mode *Testing* : les tokens **expirent tous les 7 jours**.

C'est le mur OAuth de Google, pas un défaut du code. Mais il plafonne l'adoption :
seul un développeur déjà à l'aise avec Google Cloud franchira ce setup.

### 6. Le projet est fait pour une personne

Documentation en français, installation par `git clone` (pas de paquet installable
en un clic), pas de release. Un format standard existe pourtant pour distribuer un
serveur MCP en un clic : les [Desktop Extensions
`.mcpb`](https://www.anthropic.com/engineering/desktop-extensions).

## Face à la concurrence

| | Ce projet | Serveurs MCP open-source | Connecteurs managés (claude.ai…) |
|---|---|---|---|
| Installation | lourde (app OAuth perso) | lourde (app OAuth perso) | **zéro** |
| Services | 2 en MCP (Gmail, Drive) | **12** (ex. taylorwilsdon) | quelques-uns |
| Plusieurs comptes | oui (local, par alias) | oui (multi-utilisateur OAuth 2.1) | **non** (1 compte) |
| Contrôle fin par compte | **oui** (policy, verrous, grants) | non | non |

Deux nuances honnêtes :

- L'avantage « multi-comptes » distingue ce projet **moins** qu'il n'y paraît : le
  principal serveur open-source
  ([taylorwilsdon](https://github.com/taylorwilsdon/google_workspace_mcp), plusieurs
  milliers d'étoiles) gère déjà plusieurs utilisateurs.
- Le **vrai** différenciateur de ce projet n'est donc pas le multi-comptes, mais la
  **gouvernance par compte** en local : default-deny, verrous « accès sur demande »,
  grants Drive temporaires, et
  [élicitation](https://modelcontextprotocol.io/specification/draft/client/elicitation)
  humaine. Aucun autre serveur MCP connu ne l'offre à cette granularité.

## Ce qui pourrait le rendre obsolète

- **Le multi-comptes officiel.** Si `gws` ajoute `--account`, ou si un connecteur
  claude.ai / Google gère plusieurs comptes, le cœur du wrapper disparaît (le README
  l'admet).
- **Les permissions des clients.** Claude Code sait déjà limiter les outils
  (allowlists), sandboxer le shell, et fait l'élicitation nativement. Une partie des
  garde-fous est donc reprise côté client.
- **Ce qui survivrait :** le *design* (gouvernance par compte, élicitation), pas
  forcément le code.

## Références externes

- Google Workspace CLI — demande de multi-comptes :
  [issue #293](https://github.com/googleworkspace/cli/issues/293)
- Serveur MCP concurrent :
  [taylorwilsdon/google_workspace_mcp](https://github.com/taylorwilsdon/google_workspace_mcp)
- MCP — élicitation (spécification) :
  [modelcontextprotocol.io](https://modelcontextprotocol.io/specification/draft/client/elicitation)
- Google — vérification des scopes restreints & audit CASA :
  [developers.google.com](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification)
- Anthropic — Desktop Extensions `.mcpb` :
  [anthropic.com](https://www.anthropic.com/engineering/desktop-extensions) ·
  [modelcontextprotocol/mcpb](https://github.com/modelcontextprotocol/mcpb)

## Voir aussi

- [`threat-model.md`](threat-model.md) — le modèle de menace détaillé (sécurité).
- [`../SECURITY.md`](../SECURITY.md) — garanties, ce qui n'est pas garanti, signalement.
