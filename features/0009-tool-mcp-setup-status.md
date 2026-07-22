---
id: 0009
title: Tool MCP `setup_status` (lecture seule) + `provision-gcp.sh status --json`
type: feature
priority: P2
version:
epic:
status: idea
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

- [ ] `status --json` documenté et stable (contrat du tool) ; vue texte
      inchangée par défaut.
- [ ] Tool `setup_status` exposé par le MCP, read-only, testé hermétiquement
      (sortie simulée du script).
- [ ] Depuis Claude Desktop (sans shell), « initialise mes comptes » produit
      une checklist exacte avec les commandes à exécuter.
- [ ] CLAUDE.md / mcp-setup.md référencent le tool.

## Notes

- Découle de l'ADR-0001 ; réutilise `iam_profile_states` (0005/0007).
- Le tool LIT ; toute mutation reste élicitée (unlock/grant/add_account/
  sync-iam). Ne pas exécuter gcloud depuis la gateway.
