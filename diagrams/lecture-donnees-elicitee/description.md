# Prose — source de vérité

Le chemin de LECTURE des données en session courante — le quotidien du
produit, avec le verrou « accès sur demande ».

Je demande au LLM de lire quelque chose, par exemple « mes 5 derniers mails
du compte perso ». Le LLM appelle le tool MCP (`gmail_list` sur l'alias
perso). La gateway vérifie d'abord le verrou : par défaut le profil est
verrouillé, donc refus explicite « profil verrouillé ». Ce refus n'est pas
une impasse : le LLM appelle `access_request` kind=`unlock` et me propose la
commande exacte. C'est moi qui exécute `mag unlock perso 30` dans le
terminal (Touch ID si l'authentification forte est activée).

Le LLM réessaie alors son appel : le verrou est levé, la policy autorise la
lecture, le broker exécute gws, et les données remontent jusqu'à ma réponse.
Le verrou se referme tout seul à l'expiration des minutes accordées — à la
prochaine session, redemander est normal, c'est le produit.

L'écriture Drive suit la même danse avec `access_request` kind=`grant` : le
refus de zone indique quoi demander, j'accorde une zone temporaire
(`mag grant <alias> <dossier> <heures>`), et l'écriture ne passe que sous
ce dossier.
