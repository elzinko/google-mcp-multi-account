# Prose — source de vérité

La connexion d'un NOUVEAU compte Google en cours de session, par élicitation
avec authentification forte — le flux tel que câblé par la fiche 0008 (PR #7).

Je demande au LLM de connecter une nouvelle adresse. Le LLM appelle le tool
MCP `access_request` avec kind=`add_account` (alias souhaité + email). La
gateway ne crée rien et n'exécute rien : elle renvoie un message d'élicitation
avec la commande exacte à faire exécuter, et le rappel des prérequis côté
projet GCP (test user si l'app est en Testing, rôle IAM).

Le LLM me propose la commande. C'est moi qui l'exécute dans le terminal :
`gwsa add <alias> <email>`. Si l'authentification forte est activée, Touch ID
s'affiche d'abord — un LLM ne peut pas la simuler, il faut ma présence
physique. Puis le navigateur s'ouvre : je choisis le bon compte et j'accepte
les accès (le consentement OAuth est la seconde barrière humaine). gwsa
vérifie que l'email connecté est bien celui attendu, chiffre le token,
écrit une policy prudente (default-deny) et fait une sonde IAM en lecture :
si le compte n'a pas accès au projet, la commande de réparation s'affiche
immédiatement au lieu d'un 403 surprise plus tard.
