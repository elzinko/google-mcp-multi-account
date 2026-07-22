Ce que montre ce diagramme : au quotidien, même la simple lecture des données
passe par une porte fermée par défaut. Le premier appel du LLM se heurte au
verrou du profil — un refus voulu, qui lui dit exactement quoi demander. Le
LLM te propose la commande de déverrouillage ; c'est toi qui l'exécutes, avec
Touch ID si l'authentification forte est activée. Une fois le verrou levé
pour la durée que tu as choisie, la lecture passe (sous le contrôle de la
policy) et les données remontent. Le verrou se referme ensuite tout seul :
redemander à la prochaine session n'est pas un bug, c'est le mode « accès
sur demande » qui structure le produit. L'écriture dans Drive suit la même
logique, avec en plus une zone temporaire à accorder dossier par dossier.
