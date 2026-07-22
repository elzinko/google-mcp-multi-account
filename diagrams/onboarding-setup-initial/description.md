# Prose — source de vérité

Le setup complet du projet, vu de l'utilisateur, dans la cible visée : trois
étapes humaines seulement, tout le reste guidé.

Étape 1, une seule fois : je lance `./scripts/provision-gcp.sh` dans le
terminal. Le script crée le projet GCP et active les APIs tout seul, puis me
guide pour les deux seuls gestes que Google interdit d'automatiser : créer le
client OAuth « Desktop app » et publier l'app. Il range le
`client_secret.json` téléchargé.

Étape 2, une seule fois : je branche le serveur MCP dans mon client LLM
(Claude Desktop, Cursor ou Claude Code) en collant le petit bloc de config.

Étape 3, tout le reste : je dis au LLM « initialise mes comptes ». Le LLM
interroge l'état du setup via le MCP (tool `setup_status`, cible fiche 0009),
obtient une checklist (comptes connectés ?, rôles IAM ?, app publiée ?), et me
guide par élicitation : pour chaque manque il me propose LA commande exacte
(`gwsa add …`, `sync-iam`), c'est moi qui l'exécute. Le LLM n'exécute jamais
rien qui élargisse l'accès.
