---
id: 0016
title: Porte d'entrée open-source — README copiable, SECURITY.md, licence MIT, badges
type: feature
priority: P2
version:
epic:
status: shipped
ready: 2026-07-24
pr: "#16"
created: 2026-07-24
---

## Contexte / Problème

Le README post-0010/0013 restait pénible à l'installation, et le repo manquait
des repères qu'un projet open-source affiche pour être **lisible et crédible** :

1. **Quickstart non copiable tel quel** : l'étape « brancher le MCP » renvoyait
   au bloc JSON de `docs/mcp-setup.md` alors que le script `install-claude-desktop.sh`
   (0013) existait déjà — le lecteur croyait devoir éditer du JSON à la main. Et
   il manquait un `git clone` + `cd` en tête : `ln -sf "$PWD/bin/mag" …` lancé
   depuis le home crée un **symlink cassé silencieusement**, puis
   `provision-gcp.sh` échoue avec un message opaque.
2. **Pas de licence** — statut juridique indéterminé, bloquant pour l'open-source.
3. **Pas de politique de sécurité** ni de canal de signalement, alors que le
   projet donne à des agents LLM l'accès à des comptes Google (le sujet central).
4. **Aucun badge / description / topics** — invisibilité sur GitHub, pas de
   repère build/sécurité/licence comme sur les autres projets du même auteur.

## Proposition

Refaire la **porte d'entrée** du repo (README + fichiers standards) sans nouvelle
capacité produit — de l'hygiène de présentation et de la précision :

- **README** : quickstart en 3 blocs copiables (`git clone` + `cd`, puis
  `install-claude-desktop.sh` en étape 2, `brew --prefix` portable Intel/Apple
  Silicon), warning IAM ramené à une ligne, définition profil/alias, prompt
  d'exemple pour l'étape 3, bandeau de badges, chapitre **Sécurité**, section
  **Soutenir** (lien don).
- **SECURITY.md** : mesures en place (tableau), limites honnêtes (shell libre,
  profils legacy sans policy, refus de verrou), signalement de vulnérabilité — le
  détail reste dans `docs/threat-model.md` (indirection).
- **LICENSE** : MIT.
- **Description + topics GitHub** posés sur le repo (mcp, model-context-protocol,
  claude, google-workspace, local-first, human-in-the-loop, security…).
- Corrections de précision dans `docs/mcp-setup.md` (prérequis « un profil »
  retiré — `setup_status` guide sans compte ; `GWSA_CLIENT=claude-code`) et
  `docs/architecture.md` (claim broker recalée : chemin données seulement).

## Critères d'acceptation

- [x] README : quickstart 3 blocs copiables, `git clone`+`cd` en tête, étape 2
      via `install-claude-desktop.sh`, `brew --prefix`.
- [x] Bandeau de badges (CI, licence MIT, sécurité, local-first, macOS, don).
- [x] Chapitre Sécurité (README) + section Soutenir avec lien don.
- [x] `SECURITY.md` : mesures en place, limites honnêtes, canal de signalement ;
      renvoie à `docs/threat-model.md` sans dupliquer.
- [x] `LICENSE` MIT à la racine.
- [x] Description + topics posés sur le repo GitHub.
- [x] Claims sécurité recalées sur le code (revue multi-agents) : « refuse tout »
      → « refuse tout accès aux données » ; broker = chemin données ; CI hors PR
      purement documentaires ; profils legacy sans policy documentés.
- [x] `docs/mcp-setup.md` : prérequis corrigé, `GWSA_CLIENT=claude-code` dans
      l'exemple `claude mcp add`.

## Notes

- Fiche tracée **rétroactivement** (arbitrage PO) : le travail est né d'une
  demande directe en session, pas d'un tirage de backlog. Le contenu a été livré
  dans PR #16 (déjà sur `main`).
- **Renumérotée 0014 → 0016** : trois sessions parallèles avaient réclamé le
  numéro 0014 simultanément ; sur `main`, 0014 = « refus de verrou » (#17) et
  0015 = « email métadonnée » (#18). Cette fiche prend donc 0016.
- Revue de vérification par workflow multi-agents (27 agents, 4 dimensions +
  contre-vérification adversariale) : 19 findings confirmés et corrigés — dont 3
  affirmations de sécurité plus fortes que le code, reformulées honnêtement. Deux
  gaps code révélés ont été livrés en parallèle : refus de verrou journalisés
  ([[0014]]) et email persisté hors exécution `gws` ([[0015]]). Voir aussi
  [[0003]] (vault).
- À la mise en public du repo : activer *Private vulnerability reporting*
  (sinon le lien Security Advisory de SECURITY.md renvoie un 404), et envisager
  CodeQL + OpenSSF Scorecard (réservés aux repos publics).
