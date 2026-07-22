---
id: 0010
title: README en quickstart 3 étapes — le détail part dans docs/
type: feature
priority: P2
version:
epic:
status: shipped
ready:
pr: "#13"
created: 2026-07-22
---

## Contexte / Problème

Le README actuel mêle quickstart, référence policy, admin, sécurité, tests :
il donne l'impression d'une configuration compliquée alors que la cible
utilisateur tient en trois étapes (ADR-0001, diagramme
`diagrams/onboarding-setup-initial/`). La première impression du repo dessert
le produit.

## Proposition

Réorganiser sans rien perdre :

1. **En tête du README** : quickstart 3 étapes — (1) `./scripts/provision-gcp.sh`
   (une fois), (2) brancher le MCP (bloc de config, une fois), (3) dire au
   LLM « initialise mes comptes » (guidage élicité — dépend de 0009 pour
   Desktop ; en attendant, la variante Claude Code fonctionne déjà).
2. Les sections détaillées (policy par service, zones/grants, admin web,
   strongauth, sécurité, limites) **migrent vers `docs/`** (ex.
   `docs/usage.md`, `docs/policies.md`), le README garde un sommaire d'une
   ligne par sujet.
3. Le diagramme d'architecture reste ; les diagrammes de séquence onboarding
   sont référencés.

## Critères d'acceptation

- [x] Un nouveau venu lit UNIQUEMENT le **Quickstart (3 étapes)** en tête et
      aboutit à un setup fonctionnel (les 2 gestes console restant guidés par
      le script ; l'étape 3 s'appuie sur `setup_status`, fiche 0009).
- [x] Aucune information perdue : usage/verrous/admin/strongauth → `docs/usage.md` ;
      policy/zones/grants → `docs/policies.md` ; sécurité/limites condensées avec
      lien threat-model. Liens internes tous vérifiés.
- [x] README **116 lignes** (était 270) ; un lien vers docs/ par sujet déplacé.
- [x] `tests/manuels/` et CLAUDE.md pointent toujours juste (sections Tests et
      liens inchangés).

## Notes

- Découle de l'ADR-0001. À faire après (ou avec) 0009 pour que l'étape 3 du
  quickstart soit vraie aussi dans Desktop.
