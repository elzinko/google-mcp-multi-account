Ce que montre ce diagramme : l'installation complète tient en trois étapes
humaines. D'abord le socle Google Cloud, une seule fois — un script fait tout
ce qui est automatisable et te guide pour les deux gestes que Google impose de
faire à la main dans sa console. Ensuite, brancher le serveur MCP dans ton
client LLM, une seule fois aussi. Enfin, tout le reste se passe en dialogue :
tu demandes au LLM d'initialiser tes comptes, il lit l'état du setup, te
présente ce qui manque, et te propose pour chaque manque la commande exacte à
exécuter toi-même. Lui n'exécute jamais rien qui élargisse l'accès — c'est le
principe d'élicitation qui structure tout le projet.
