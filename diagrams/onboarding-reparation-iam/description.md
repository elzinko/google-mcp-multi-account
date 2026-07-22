# Prose — source de vérité

La détection et la réparation de la dérive IAM — le flux câblé par les fiches
0005 et 0007 (PRs #5 et #6).

Contexte : gws attache le projet GCP de l'app OAuth comme « quota project » à
chaque appel. Un compte connecté qui n'a pas le rôle serviceUsageConsumer sur
ce projet reçoit un 403 à chaque appel API, alors que son token est valide.

Deux portes d'entrée. Soit le LLM rencontre le 403 en travaillant et me le
signale avec la commande de réparation (heuristique CLAUDE.md + détecteur
iam-check.py). Soit je lance moi-même `provision-gcp.sh status` (lecture
seule) : il compare les emails des profils connectés aux membres de l'IAM
policy du projet et liste chaque compte sans rôle, avec sa commande.

La réparation est à moi : `provision-gcp.sh sync-iam` parcourt les comptes
qui manquent, me demande confirmation pour chacun, et accorde le rôle via
gcloud (dans MA session gcloud de propriétaire du projet — pas celle du LLM).
C'est idempotent : les comptes déjà en place répondent « déjà OK », et
relancer quand tout va bien ne change rien. La propagation prend environ
deux minutes, puis les appels du compte passent.
