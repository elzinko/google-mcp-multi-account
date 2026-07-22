---
id: 0009
title: Tool MCP `setup_status` (lecture seule) + `provision-gcp.sh status --json`
type: feature
priority: P2
version:
epic:
status: in-progress
ready:
pr:
created: 2026-07-22
---

## Contexte / Problème

Dans Claude Desktop il n'y a pas de shell : le serveur MCP est le seul pont.
Tout le diagnostic de setup (projet provisionné ?, app publiée ?, comptes
connectés ?, rôle IAM par compte ?) n'existe qu'en terminal — un utilisateur
Desktop ne peut pas être guidé pour l'onboarding (« initialise mes comptes »)
ni pour le dépannage. Cf. ADR-0001 (option C retenue).

## Proposition

1. `provision-gcp.sh status --json` : sortie machine (mêmes informations que
   la vue humaine — projet, published, secret, comptes {alias, email,
   iam: ok|missing|unknown, remédiation}) ; la vue texte reste le défaut.
2. Tool MCP **`setup_status`** (lecture seule, aucun paramètre) : la gateway
   appelle le script et renvoie le JSON + un champ `next_actions` (liste de
   commandes d'élicitation prêtes à proposer). Aucune mutation, jamais.
3. Le LLM déroule alors le « init guidé » : checklist, une commande proposée
   par manque, l'humain exécute (diagramme
   `diagrams/onboarding-setup-initial/`).

## Critères d'acceptation

- [x] `status --json` : sortie machine (`gateway/setup_status.py`, réutilisée
      par le script et le tool) ; la vue texte reste le défaut.
- [x] Tool `setup_status` exposé par le MCP, read-only, testé hermétiquement
      (dégradation gracieuse sans projet/gcloud + `next_actions`).
- [x] Un LLM obtient la checklist exacte + les commandes par manque
      (`next_actions`) ; validé sur le vrai projet (mw → missing + sync-iam).
      *Reste à constater en conditions réelles Desktop (sans shell) au
      prochain usage — l'appel tool est identique.*
- [x] CLAUDE.md (règle 2) / docs/mcp-setup.md (table des tools) référencent
      le tool.

**Note d'implémentation** : la lecture de l'email d'un profil verrouillé
(nécessaire au check IAM) se fait hors du verrou — c'est une métadonnée
d'identité, pas un accès aux données. `setup_status` ne mute jamais rien ;
l'IAM se dégrade en « unknown » si gcloud est absent (contexte Desktop).

## Notes

- Découle de l'ADR-0001 ; réutilise `iam_profile_states` (0005/0007).
- Le tool LIT ; toute mutation reste élicitée (unlock/grant/add_account/
  sync-iam). Ne pas exécuter gcloud depuis la gateway.
- **Complémentarité avec l'admin web** (`admin/server.js`,
  http://127.0.0.1:4877) : l'admin est le cockpit de *l'humain*
  (visualiser + configurer : comptes, verrous, policies, zones, journal,
  révocation) ; `setup_status` est la même visibilité pour *le LLM*.
  Extension candidate (validée sur le principe par le PO, 2026-07-22 —
  « j'aime cette idée de visualisation ») : un panneau « Setup » dans
  l'admin affichant l'état provisioning/IAM/publication — même source que
  `status --json`, deux vues.
- **Démarrage de l'admin** (constat 2026-07-22) : aujourd'hui 100 % manuel
  (`node admin/server.js`) — la config MCP ne lance que la gateway, qui
  auto-démarre le broker (Popen détaché), jamais l'admin. À trancher ici :
  laisser manuel (cycle de vie humain assumé), ou auto-démarrage launchd au
  login. NE PAS la faire lancer par le process MCP : sa vie serait couplée
  au client LLM, à rebours du rôle « cockpit humain ».
