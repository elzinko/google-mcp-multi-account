# Backlog features & bugs — google-mcp-multi-account

> Index auto-généré (`regen-backlog.sh` mega-city, via `/ezk-backlog regen`) — **ne pas éditer à la main**. Source de vérité = le front-matter de chaque fiche.
> 1 fiche / sujet · 1 PR / feature · backlog commité sur `main`. Statuts : 💡 idea · 🔴 todo · 🟠 in-progress · ⛔ blocked · ✅ shipped.

| # | Titre | Type | Prio | Version | Épic | Statut | PR |
|---|-------|------|------|---------|------|--------|----|
| 0023 | Versionner et déployer le MCP en local, découplé du code source de travail | feature | P0 |  |  | ✅ shipped | #25 |
| 0004 | Broker daemon local Phase 2 A — gws derrière socket loopback | feature | P1 |  |  | ✅ shipped | 12114ac |
| 0005 | Onboarding des comptes — chaîne complète élicitée (IAM compris), drift visible | feature | P1 |  |  | ✅ shipped | #5 |
| 0012 | Panneau « Santé du setup » + bouton « Réparer l'accès IAM » dans l'admin | feature | P1 |  |  | ✅ shipped | #14 |
| 0014 | Journaliser les refus de verrou dans usage.jsonl (decision:refus, reason:locked) | bug | P1 |  |  | ✅ shipped | #17 |
| 0015 | Email de profil = métadonnée persistée (.email) — zéro exécution gws hors broker | refactor | P1 |  |  | ✅ shipped | #18 |
| 0019 | English public surfaces — landing, docs & product copy | feature | P1 |  | 0017 | 🔴 todo |  |
| 0024 | Fiabiliser les tools Gmail/Drive du MCP — brouillon cassé, Drive sans contenu ni propriétaire | bug | P1 |  |  | ✅ shipped | #26 |
| 0025 | Couloirs étanches — chaque version branchée parle à son propre broker | bug | P1 |  |  | ✅ shipped | #27 |
| 0029 | Publier et mettre à jour en une commande (release semver + update façon installeur) | feature | P1 |  |  | ✅ shipped | #28 |
| 0030 | Poste de commande versionné — gwsa update/release et le lien PATH sur la copie installée | feature | P1 |  |  | ✅ shipped | #30 |
| 0031 | La suite de tests ne doit jamais pouvoir toucher le PATH réel | bug | P1 |  |  | ✅ shipped | #31 |
| 0037 | Sémantique de la suppression en zone — corbeille = suppression, racine de zone immuable, avertissement | feature | P1 |  |  | ✅ shipped | #47 |
| 0043 | Lire, copier, téléverser — contenu Drive et pièces jointes Gmail via MCP | feature | P1 |  |  | ✅ shipped | #73 |
| 0061 | Déconnexion — modale de confirmation + bouton compact | feature | P1 | v0.4.0 | 0060 | 🔴 todo |  |
| 0062 | Admin header — réordonner actions + mode Avancé + retirer texte long | feature | P1 | v0.4.0 | 0060 | 🔴 todo |  |
| 0063 | Remplacer « Tout verrouiller » par icône cadenas + modale d'impact | feature | P1 | v0.4.0 | 0060 | 🔴 todo |  |
| 0064 | Améliorer le bouton retour « ‹ Comptes » (style + position) | feature | P1 | v0.4.0 | 0060 | 🔴 todo |  |
| 0065 | Masquer « + Connecter un compte » en vue détail | feature | P1 | v0.4.0 | 0060 | 🔴 todo |  |
| 0066 | Journal — lisibilité (wrap colonnes, plus de scroll horizontal) | feature | P1 | v0.4.0 | 0060 | 🔴 todo |  |
| 0067 | Admin branding — corriger le titre de page | feature | P1 | v0.4.0 | 0060 | 🔴 todo |  |
| 0002 | Durcir le modèle de policy — décisions « default-deny » soulevées par l'audit | feature | P2 |  |  | ✅ shipped | #12 |
| 0007 | Provisioning GCP idempotent/déclaratif — durcir provision-gcp.sh ou passer à Terraform | feature | P2 |  |  | ✅ shipped | #10 |
| 0008 | Connexion dynamique d'un nouveau compte via élicitation forte (access_request kind=add_account) | feature | P2 |  |  | ✅ shipped | #7 |
| 0009 | Tool MCP `setup_status` (lecture seule) + `provision-gcp.sh status --json` | feature | P2 |  |  | ✅ shipped | #11 |
| 0010 | README en quickstart 3 étapes — le détail part dans docs/ | feature | P2 |  |  | ✅ shipped | #13 |
| 0011 | `gwsa admin` — démarrer/arrêter l'interface web en un geste, proposé par l'élicitation | feature | P2 |  |  | ✅ shipped | #9 |
| 0013 | Brancher le serveur MCP dans Claude Desktop en un geste (script idempotent) | feature | P2 |  |  | ✅ shipped | #15 |
| 0016 | Porte d'entrée open-source — README copiable, SECURITY.md, licence MIT, badges | feature | P2 |  |  | ✅ shipped | #16 |
| 0022 | Doc de critique technique lisible (forces / limites / risques) référencée au README | feature | P2 |  |  | ✅ shipped | #23 |
| 0027 | Déployer un commit non taggé pour essayer une PR (couloir jetable) | feature | P2 |  |  | ✅ shipped | #48 |
| 0032 | La notification Touch ID doit nommer le compte et le produit, pas l'alias seul | feature | P2 |  |  | ✅ shipped | #48 |
| 0036 | Refonte des cartes profil de l'admin — liste, page de compte, zones (spec maquette v11) | feature | P2 |  |  | ✅ shipped | #44 |
| 0040 | Le déploiement branche Claude Desktop mais pas Claude Code (CLI) — généraliser | feature | P2 |  |  | ✅ shipped | #43 |
| 0041 | Clarifier l'écart policy admin ↔ surface MCP (Drive copie, contenu, modification) | bug | P2 |  |  | 🟠 in-progress | #52 |
| 0044 | Sous strongauth, le dialogue Touch ID nomme « swift-frontend » au lieu du produit | bug | P2 |  |  | ✅ shipped | #74 |
| 0045 | Droits par session et par projet git — état des lieux, écarts, pistes | feature | P2 |  |  | 🟠 in-progress |  |
| 0046 | CLI locale pour déployer des sandboxes temporaires (branche / worktree) | feature | P2 |  |  | 🟠 in-progress |  |
| 0047 | Au moment d'autoriser un accès, nommer le compte (email) — pas seulement l'alias | feature | P2 |  |  | ✅ shipped | #75 |
| 0068 | Accessibilité — focus-visible + reduced-motion (cadenas/modales/boutons) | feature | P2 | v0.4.0 | 0060 | 🔴 todo |  |
| 0069 | Docs in-app — rework orientation utilisateur | feature | P2 | v0.4.0 | 0060 | 🔴 todo |  |
| 0070 | README — quickstart + usage par persona + permissions + contribution | feature | P2 | v0.4.0 | 0060 | 🔴 todo |  |
| 0071 | GitHub metadata — description, homepage, topics + badges | chore | P2 | v0.4.0 | 0060 | 🔴 todo |  |
| 0001 | Élicitation signée — faire monter `gwsa strongauth` de la présence à la signature | feature | P3 |  |  | 🟠 in-progress |  |

## 🧭 Épics (jamais tirables — tirer leurs enfants ready, ADR-0017)

| # | Titre | Type | Prio | Version | Épic | Statut | PR |
|---|-------|------|------|---------|------|--------|----|
| 0060 | Admin UX/UI refresh + docs/README + GitHub metadata | epic | P1 | v0.4.0 |  | 🔴 todo |  |
| 0017 | Généraliser le projet à d'autres utilisateurs que l'auteur | epic | P2 |  |  | 💡 idea |  |

## 💡 Idées (non groomées)

| # | Titre | Type | Prio | Version | Épic | Statut | PR |
|---|-------|------|------|---------|------|--------|----|
| 0006 | Harnais hybride pour les tests manuels — script pour la mécanique, LLM pour la glu | feature | P2 |  |  | 💡 idea |  |
| 0026 | Savoir quelle version répond — version annoncée par les tools, dérive détectée | feature | P2 |  |  | 💡 idea |  |
| 0035 | Accès rapide à l'admin + visualisation des zones (icône barre de menus ?) | feature | P2 |  |  | 💡 idea |  |
| 0038 | Créer un dossier-zone rapidement, geste humain (sans passer par le LLM) | feature | P2 |  |  | 💡 idea |  |
| 0039 | Bannir « jeton/token » des surfaces utilisateur — un seul vocabulaire (accès / connexion) | chore | P2 |  |  | 💡 idea |  |
| 0042 | Version visible dans le connecteur MCP + mise à jour guidée | feature | P2 | V2 |  | 💡 idea |  |
| 0003 | Vault credentials hors périmètre agent (Phase 2.1) | feature | P3 |  |  | 💡 idea |  |
| 0018 | Cross-platform — faire tourner le projet hors macOS (Linux, Intel) | feature | P3 |  | 0017 | 💡 idea |  |
| 0021 | Élargir la couverture MCP — Calendar, Docs, Sheets, Tasks (et écritures) | feature | P3 |  | 0017 | 💡 idea |  |
| 0028 | Ménage des versions déployées (+ CHANGELOG et releases GitHub) | chore | P3 |  |  | 💡 idea |  |
| 0034 | Mettre à jour le protocole du test manuel drive-2-comptes (limites périmées + nouvelles phases) | chore | P3 |  |  | 💡 idea |  |

> Livrées (`done/`) : 0002, 0004, 0005, 0007, 0008, 0009, 0010, 0011, 0012, 0013, 0014, 0015, 0016, 0020, 0022, 0023, 0024, 0025, 0027, 0029, 0030, 0031, 0032, 0036, 0037, 0040, 0043, 0044, 0047, 0059, 0072.
