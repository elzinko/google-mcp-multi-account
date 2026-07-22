Ce que montre ce diagramme : un LLM peut demander la connexion d'un nouveau
compte Google, mais ne peut jamais la faire lui-même. Sa demande passe par le
serveur MCP, qui répond uniquement par la commande exacte à exécuter — rien
n'est créé à ce stade. C'est toi qui lances cette commande, et deux barrières
physiques se dressent alors : Touch ID (présence devant le Mac) puis le
consentement OAuth dans le navigateur (choisir le compte, accepter). Une fois
connecté, le compte reçoit d'office une policy prudente, et une sonde vérifie
immédiatement son accès au projet Google Cloud — si le rôle IAM manque, la
commande de réparation s'affiche tout de suite plutôt que d'échouer en
silence au premier appel.
