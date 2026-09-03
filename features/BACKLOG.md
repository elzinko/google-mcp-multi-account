# Backlog features & bugs — google-multi-account

> Index auto-généré (`regen-backlog.sh` mega-city, via `/ezk-backlog regen`) — **ne pas éditer à la main**. Source de vérité = le front-matter de chaque fiche.
> Guide du dossier : [README.md](README.md). Statuts : 💡 idea · 🔴 todo · 🟠 in-progress · ⛔ blocked · ✅ shipped.

> 📋 Séquence décidée (curée, hors index) : [PLAN.md](PLAN.md).

| # | Titre | Type | Prio | Version | Épic | Produit | Statut | PR |
|---|-------|------|------|---------|------|---------|--------|----|
| [0023](done/0023-versionner-deployer-mcp-local.md) | Versionner et déployer le MCP en local, découplé du code source de travail | feature | P0 |  |  |  | ✅ shipped | #25 |
| [0095](done/0095-design-system-fondations-tokens.md) | Design system — fondations (tokens d'échelles + carte unifiée) | feature | P0 |  | 0060 | google-mcp-multi-account | ✅ shipped | #128 |
| [0096](0096-socle-rendu-sur-html-echappant.md) | Socle de rendu sûr — fonction html`` échappant par défaut + filet de tests node | feature | P0 |  | 0060 | google-mcp-multi-account | 🔴 todo |  |
| [0004](done/0004-broker-daemon-phase-2a.md) | Broker daemon local Phase 2 A — gws derrière socket loopback | feature | P1 |  |  |  | ✅ shipped | 12114ac |
| [0005](done/0005-onboarding-comptes-iam-elicitation.md) | Onboarding des comptes — chaîne complète élicitée (IAM compris), drift visible | feature | P1 |  |  |  | ✅ shipped | #5 |
| [0012](done/0012-admin-bouton-reparation-iam.md) | Panneau « Santé du setup » + bouton « Réparer l'accès IAM » dans l'admin | feature | P1 |  |  |  | ✅ shipped | #14 |
| [0014](done/0014-journaliser-refus-verrou-usage-jsonl.md) | Journaliser les refus de verrou dans usage.jsonl (decision:refus, reason:locked) | bug | P1 |  |  |  | ✅ shipped | #17 |
| [0015](done/0015-email-metadonnee-persistee-hors-verrou.md) | Email de profil = métadonnée persistée (.email) — zéro exécution gws hors broker | refactor | P1 |  |  |  | ✅ shipped | #18 |
| [0019](0019-documentation-anglaise.md) | English public surfaces — landing, docs & product copy | feature | P1 |  | 0017 |  | 🔴 todo |  |
| [0020](done/0020-packaging-installable.md) | Installer & mettre à jour sans clone — installeur curl puis tap Homebrew | feature | P1 |  | 0017 |  | ✅ shipped | #78 |
| [0024](done/0024-fiabiliser-tools-gmail-drive-mcp.md) | Fiabiliser les tools Gmail/Drive du MCP — brouillon cassé, Drive sans contenu ni propriétaire | bug | P1 |  |  |  | ✅ shipped | #26 |
| [0025](done/0025-couloirs-etanches-broker-par-version.md) | Couloirs étanches — chaque version branchée parle à son propre broker | bug | P1 |  |  |  | ✅ shipped | #27 |
| [0029](done/0029-release-et-update-en-une-commande.md) | Publier et mettre à jour en une commande (release semver + update façon installeur) | feature | P1 |  |  |  | ✅ shipped | #28 |
| [0030](done/0030-poste-de-commande-versionne.md) | Poste de commande versionné — mag update/release et le lien PATH sur la copie installée | feature | P1 |  |  |  | ✅ shipped | #30 |
| [0031](done/0031-tests-hors-du-path-reel.md) | La suite de tests ne doit jamais pouvoir toucher le PATH réel | bug | P1 |  |  |  | ✅ shipped | #31 |
| [0037](done/0037-semantique-suppression-en-zone.md) | Sémantique de la suppression en zone — corbeille = suppression, racine de zone immuable, avertissement | feature | P1 |  |  |  | ✅ shipped | #47 |
| [0043](done/0043-lire-copier-televerser-drive-et-pj-gmail.md) | Lire, copier, téléverser — contenu Drive et pièces jointes Gmail via MCP | feature | P1 |  |  |  | ✅ shipped | #73 |
| [0059](done/0059-gwsa-resolve-folder-vault.md) | mag ne résout plus un dossier par son nom depuis le vault (grant / policy zone) | bug | P1 |  |  |  | ✅ shipped | #77 |
| [0061](done/0061-deconnexion-modale-confirmation.md) | Déconnexion — modale de confirmation + bouton compact | feature | P1 | v0.4.0 | 0060 |  | ✅ shipped | #112 |
| [0062](done/0062-admin-header-mode-avance.md) | Admin header — réordonner actions + mode Avancé + retirer texte long | feature | P1 | v0.4.0 | 0060 |  | ✅ shipped | #112 |
| [0063](done/0063-tout-verrouiller-icone-modale.md) | Remplacer « Tout verrouiller » par icône cadenas + modale d'impact | feature | P1 | v0.4.0 | 0060 |  | ✅ shipped | #112 |
| [0064](done/0064-bouton-retour-comptes.md) | Améliorer le bouton retour « ‹ Comptes » (style + position) | feature | P1 | v0.4.0 | 0060 |  | ✅ shipped | #112 |
| [0065](done/0065-masquer-connecter-compte-en-detail.md) | Masquer « + Connecter un compte » en vue détail | feature | P1 | v0.4.0 | 0060 |  | ✅ shipped | #112 |
| [0066](done/0066-journal-lisibilite.md) | Journal — lisibilité (wrap colonnes, plus de scroll horizontal) | feature | P1 | v0.4.0 | 0060 |  | ✅ shipped | #112 |
| [0067](done/0067-admin-branding-titre.md) | Admin branding — corriger le titre de page | feature | P1 | v0.4.0 | 0060 |  | ✅ shipped | #112 |
| [0074](0074-durcir-la-v1-punch-list-lancement.md) | Durcir la v1 — punch-list de lancement (doc, tests, hygiène) | feature | P1 | v1.0 |  |  | 🟠 in-progress |  |
| [0078](done/0078-approbation-passkey-archi-actuelle.md) | Approbation par passkey depuis le téléphone (archi actuelle, Mac holder) | feature | P1 |  | 0077 |  | ✅ shipped | #113 |
| [0080](done/0080-durcir-capacites-fines-session.md) | Durcir la couche capacités fines de session (suite revue Codex #110) | feature | P1 |  | 0082 |  | ✅ shipped | #118 |
| [0085](done/0085-figer-unlock-zones-sous-session.md) | Figer unlock de compte + zones Drive à la création d'une sous-session (isolation complète) | bug | P1 |  | 0082 |  | ✅ shipped | #119 |
| [0097](0097-composants-transverses.md) | Composants transverses — pastille de droit accessible, callout, boutons, coquille modale | feature | P1 |  | 0060 | google-mcp-multi-account | 🔴 todo |  |
| [0098](0098-micro-routeur-vues.md) | Micro-routeur — formaliser les vues (pages vs modales), un seul registre de poll | refactor | P1 |  | 0060 | google-mcp-multi-account | 🔴 todo |  |
| [0099](done/0099-sessions-pilote-tri-liste-vignettes.md) | Sessions — tranche pilote du design system (cartes régulières + tri + bascule liste/vignettes) | feature | P1 |  | 0060 | google-mcp-multi-account | ✅ shipped | #128 |
| [0102](done/0102-journal-page-monitoring-filtres-par-session.md) | Journal en page dédiée — filtres + journal par session (virage monitoring) | feature | P1 |  | 0060 | google-mcp-multi-account | ✅ shipped | #128 |
| [0104](done/0104-app-shell-responsive-mobile.md) | App shell responsive — navigation et rendu mobile pro (bottom-nav + top-bar) | feature | P1 |  | 0060 | google-mcp-multi-account | ✅ shipped | #128 |
| [0107](0107-vue-compte-droits-sur-place.md) | Vue compte — piloter les droits sur place (remplacer la modale Policy) + nettoyer la liste | feature | P1 |  | 0060 | google-mcp-multi-account | 🔴 todo |  |
| [0002](done/0002-durcir-modele-policy-default-deny.md) | Durcir le modèle de policy — décisions « default-deny » soulevées par l'audit | feature | P2 |  |  |  | ✅ shipped | #12 |
| [0007](done/0007-provisioning-idempotent-declaratif.md) | Provisioning GCP idempotent/déclaratif — durcir provision-gcp.sh ou passer à Terraform | feature | P2 |  |  |  | ✅ shipped | #10 |
| [0008](done/0008-connexion-dynamique-compte-elicitation.md) | Connexion dynamique d'un nouveau compte via élicitation forte (access_request kind=add_account) | feature | P2 |  |  |  | ✅ shipped | #7 |
| [0009](done/0009-tool-mcp-setup-status.md) | Tool MCP `setup_status` (lecture seule) + `provision-gcp.sh status --json` | feature | P2 |  |  |  | ✅ shipped | #11 |
| [0010](done/0010-readme-quickstart-3-etapes.md) | README en quickstart 3 étapes — le détail part dans docs/ | feature | P2 |  |  |  | ✅ shipped | #13 |
| [0011](done/0011-gwsa-admin-demarrage-un-geste.md) | `mag admin` — démarrer/arrêter l'interface web en un geste, proposé par l'élicitation | feature | P2 |  |  |  | ✅ shipped | #9 |
| [0013](done/0013-brancher-claude-desktop-auto.md) | Brancher le serveur MCP dans Claude Desktop en un geste (script idempotent) | feature | P2 |  |  |  | ✅ shipped | #15 |
| [0016](done/0016-readme-porte-entree-open-source.md) | Porte d'entrée open-source — README copiable, SECURITY.md, licence MIT, badges | feature | P2 |  |  |  | ✅ shipped | #16 |
| [0022](done/0022-doc-critique-technique.md) | Doc de critique technique lisible (forces / limites / risques) référencée au README | feature | P2 |  |  |  | ✅ shipped | #23 |
| [0027](done/0027-deployer-un-commit-non-tagge.md) | Déployer un commit non taggé pour essayer une PR (couloir jetable) | feature | P2 |  |  |  | ✅ shipped | #48 |
| [0032](done/0032-touchid-nomme-compte-et-produit.md) | La notification Touch ID doit nommer le compte et le produit, pas l'alias seul | feature | P2 |  |  |  | ✅ shipped | #48 |
| [0036](done/0036-admin-clarte-cartes-profil.md) | Refonte des cartes profil de l'admin — liste, page de compte, zones (spec maquette v11) | feature | P2 |  |  |  | ✅ shipped | #44 |
| [0040](done/0040-brancher-mcp-claude-code.md) | Le déploiement branche Claude Desktop mais pas Claude Code (CLI) — généraliser | feature | P2 |  |  |  | ✅ shipped | #43 |
| [0041](done/0041-ecart-policy-surface-mcp.md) | Clarifier l'écart policy admin ↔ surface MCP (Drive copie, contenu, modification) | bug | P2 |  |  |  | ✅ shipped | #52 |
| [0044](done/0044-touchid-signe-nom-produit.md) | Sous strongauth, le dialogue Touch ID nomme « swift-frontend » au lieu du produit | bug | P2 |  |  |  | ✅ shipped | #74 |
| [0045](0045-capacites-projet-signees.md) | Droits par session et par projet git — état des lieux, écarts, pistes | feature | P2 |  | 0082 |  | 🟠 in-progress |  |
| [0046](0046-sandbox-deploy-cli.md) | CLI locale pour déployer des sandboxes temporaires (branche / worktree) | feature | P2 |  |  |  | 🟠 in-progress |  |
| [0047](done/0047-nommer-le-compte-au-moment-d-autoriser.md) | Au moment d'autoriser un accès, nommer le compte (email) — pas seulement l'alias | feature | P2 |  |  |  | ✅ shipped | #75 |
| [0068](done/0068-accessibilite-focus-reduced-motion.md) | Accessibilité — focus-visible + reduced-motion (cadenas/modales/boutons) | feature | P2 | v0.4.0 | 0060 |  | ✅ shipped | #112 |
| [0069](done/0069-docs-in-app-orientation-user.md) | Docs in-app — rework orientation utilisateur | feature | P2 | v0.4.0 | 0060 |  | ✅ shipped | #112 |
| [0070](0070-readme-onboarding-personas.md) | README — quickstart + usage par persona + permissions + contribution | feature | P2 | v0.4.0 | 0060 |  | 🔴 todo |  |
| [0071](done/0071-github-metadata-topics.md) | GitHub metadata — description, homepage, topics + badges | chore | P2 | v0.4.0 | 0060 |  | ✅ shipped |  |
| [0072](done/0072-site-doc-en-ligne.md) | Site de doc en ligne (MkDocs Material + landing) déployé sur Vercel | feature | P2 |  | 0017 |  | ✅ shipped | #79 |
| [0076](done/0076-droits-par-session-phase-a.md) | Droits par session (Phase A desktop) — identité par consentement, jeton porté, config fine | feature | P2 |  | 0082 |  | ✅ shipped | #108, #110 |
| [0081](0081-durcir-updater-rollback-renommage.md) | Durcir updater/deploy — rollback à travers le renommage mag & liens PATH cassés | bug | P2 |  |  |  | 🔴 todo |  |
| [0083](done/0083-durcir-approbation-passkey-distante.md) | Durcir la couche d'approbation passkey distante (suite revue Codex #113) | feature | P2 |  | 0077 |  | ✅ shipped | #126 |
| [0084](done/0084-durcir-consume-nonce-toctou.md) | Durcir consume_nonce contre une course TOCTOU inter-process (anti-rejeu partagé) | bug | P2 |  |  |  | ✅ shipped | #125 |
| [0086](0086-raffinements-audit-migration-capacites-session.md) | Raffinements audit + migration de la couche capacités de session (suite revue PR #118) | bug | P2 |  | 0082 |  | 🔴 todo |  |
| [0087](done/0087-install-branchement-clients-opt-in.md) | install.sh — brancher les clients LLM en opt-in (pas opt-out) | feature | P2 |  |  |  | ✅ shipped | #123 |
| [0088](done/0088-install-help-curl-pipe.md) | Aide de install.sh vide sous « curl \| bash » (--help relit $0) | bug | P2 |  |  |  | ✅ shipped | #124 |
| [0089](0089-choix-profil-navigateur-oauth-add.md) | Choisir le profil navigateur (Chrome/…) à l'ouverture OAuth de `mag add` | feature | P2 |  |  |  | 🔴 todo |  |
| [0091](0091-updater-rollback-ergonomique.md) | Updater — rollback ergonomique : commande revert, messages CLI, help enrichi | feature | P2 |  |  |  | 🔴 todo |  |
| [0092](0092-bascule-gwsa-mag-path-refresh-terminal.md) | Finaliser la bascule gwsa→mag côté PATH + guider le refresh du terminal | feature | P2 |  |  |  | 🔴 todo |  |
| [0094](0094-sessions-page-dediee-reactive.md) | Panneau Sessions LLM — page dédiée réactive et plus lisible (au lieu d'une modale) | feature | P2 |  | 0060 | google-mcp-multi-account | 🟠 in-progress |  |
| [0100](0100-deploiement-ecrans-contraste-aa.md) | Déploiement du design system écran par écran + passe contraste AA | feature | P2 |  | 0060 | google-mcp-multi-account | 🔴 todo |  |
| [0103](done/0103-refonte-barre-navigation-admin.md) | Refonte de la barre de navigation de l'admin (header/menu standard) | feature | P2 |  | 0060 | google-mcp-multi-account | ✅ shipped | #128 |
| [0106](0106-vue-compte-orientee-sessions.md) | Vue compte orientée sessions — compteur, liste des sessions et droits par session | feature | P2 |  |  | google-mcp-multi-account | 🔴 todo |  |
| [0001](0001-elicitation-signee-strongauth-v2.md) | Élicitation signée — faire monter `mag strongauth` de la présence à la signature | feature | P3 |  |  |  | 🟠 in-progress |  |
| [0090](0090-documenter-statut-oauth-verification.md) | Documenter et outiller le statut OAuth (warning « non vérifiée » + Testing→Production) | feature | P3 |  |  |  | 🔴 todo |  |
| [0093](0093-coherence-nommage-mag-produit-mcp.md) | Cohérence de nommage — relier `mag` / google-multi-account / repo sans casser le MCP | feature | P3 |  |  |  | 🔴 todo |  |

## 🧭 Épics (jamais tirables — tirer leurs enfants ready, ADR-0017)

| # | Titre | Type | Prio | Version | Épic | Produit | Statut | PR |
|---|-------|------|------|---------|------|---------|--------|----|
| [0060](0060-admin-ux-ui-refresh.md) | Admin UX/UI refresh + docs/README + GitHub metadata | epic | P1 | v0.4.0 |  |  | 🔴 todo |  |
| [0077](0077-acces-mobile-souverain.md) | Accès mobile souverain — approbation passkey + holder natif | epic | P1 |  |  |  | 🔴 todo |  |
| [0082](0082-droits-par-session.md) | Droits par session — isolation & capacités fines par conversation | epic | P1 |  |  |  | 🟠 in-progress |  |
| [0105](done/0105-refonte-admin-cockpit.md) | Refonte de l'admin — adopter le design system « Cockpit » (par écran) | epic | P1 |  |  | google-mcp-multi-account | ✅ shipped | #128 |
| [0017](0017-generaliser-autres-utilisateurs.md) | Généraliser le projet à d'autres utilisateurs que l'auteur | epic | P2 |  |  |  | 💡 idea |  |

## 💡 Idées (non groomées)

| # | Titre | Type | Prio | Version | Épic | Produit | Statut | PR |
|---|-------|------|------|---------|------|---------|--------|----|
| [0101](0101-nom-de-session-fourni-par-le-client.md) | Nom lisible de session, fourni par le client MCP | feature | P1 |  | 0082 | google-mcp-multi-account | 💡 idea |  |
| [0108](0108-session-demande-sous-ensemble-droits-compte.md) | Session — demander un sous-ensemble des droits du compte (accès fin, vérifiable par session) | feature | P1 |  | 0082 | google-mcp-multi-account | 💡 idea |  |
| [0006](0006-harnais-test-manuel-hybride.md) | Harnais hybride pour les tests manuels — script pour la mécanique, LLM pour la glu | feature | P2 |  |  |  | 💡 idea |  |
| [0026](0026-savoir-quelle-version-repond.md) | Savoir quelle version répond — version annoncée par les tools, dérive détectée | feature | P2 |  |  |  | 💡 idea |  |
| [0035](0035-admin-acces-rapide-et-visu-zones.md) | Accès rapide à l'admin + visualisation des zones (icône barre de menus ?) | feature | P2 |  |  |  | 💡 idea |  |
| [0038](0038-creer-dossier-zone-rapidement.md) | Créer un dossier-zone rapidement, geste humain (sans passer par le LLM) | feature | P2 |  |  |  | 💡 idea |  |
| [0039](0039-harmoniser-vocabulaire-jeton.md) | Bannir « jeton/token » des surfaces utilisateur — un seul vocabulaire (accès / connexion) | chore | P2 |  |  |  | 💡 idea |  |
| [0042](0042-version-connecteur-et-maj.md) | Version visible dans le connecteur MCP + mise à jour guidée | feature | P2 | V2 |  |  | 💡 idea |  |
| [0079](0079-modele-soutenabilite-freemium.md) | Modèle de soutenabilité — freemium (cœur libre + options payantes) | feature | P2 |  |  |  | 💡 idea |  |
| [0003](0003-vault-credentials-hors-perimetre-agent.md) | Vault credentials hors périmètre agent (Phase 2.1) | feature | P3 |  |  |  | 💡 idea |  |
| [0018](0018-cross-platform-hors-macos.md) | Cross-platform — faire tourner le projet hors macOS (Linux, Intel) | feature | P3 |  | 0017 |  | 💡 idea |  |
| [0021](0021-couverture-mcp-elargie.md) | Élargir la couverture MCP — Calendar, Docs, Sheets, Tasks (et écritures) | feature | P3 |  | 0017 |  | 💡 idea |  |
| [0028](0028-menage-des-versions-deployees.md) | Ménage des versions déployées (+ CHANGELOG et releases GitHub) | chore | P3 |  |  |  | 💡 idea |  |
| [0034](0034-maj-protocole-test-manuel-drive.md) | Mettre à jour le protocole du test manuel drive-2-comptes (limites périmées + nouvelles phases) | chore | P3 |  |  |  | 💡 idea |  |
| [20260903155243753](20260903155243753_journal-filtre-date.md) | Journal — filtre par date (la dimension manquante) | feature | P3 |  | 0060 | google-mcp-multi-account | 💡 idea |  |
| [20260903155243879](20260903155243879_mobile-cibles-tactiles-44px.md) | Admin mobile — cibles tactiles à 44 px (barre haute) | bug | P3 |  | 0060 | google-mcp-multi-account | 💡 idea |  |

> Livrées (`done/`) : [0002](done/0002-durcir-modele-policy-default-deny.md), [0004](done/0004-broker-daemon-phase-2a.md), [0005](done/0005-onboarding-comptes-iam-elicitation.md), [0007](done/0007-provisioning-idempotent-declaratif.md), [0008](done/0008-connexion-dynamique-compte-elicitation.md), [0009](done/0009-tool-mcp-setup-status.md), [0010](done/0010-readme-quickstart-3-etapes.md), [0011](done/0011-gwsa-admin-demarrage-un-geste.md), [0012](done/0012-admin-bouton-reparation-iam.md), [0013](done/0013-brancher-claude-desktop-auto.md), [0014](done/0014-journaliser-refus-verrou-usage-jsonl.md), [0015](done/0015-email-metadonnee-persistee-hors-verrou.md), [0016](done/0016-readme-porte-entree-open-source.md), [0020](done/0020-packaging-installable.md), [0022](done/0022-doc-critique-technique.md), [0023](done/0023-versionner-deployer-mcp-local.md), [0024](done/0024-fiabiliser-tools-gmail-drive-mcp.md), [0025](done/0025-couloirs-etanches-broker-par-version.md), [0027](done/0027-deployer-un-commit-non-tagge.md), [0029](done/0029-release-et-update-en-une-commande.md), [0030](done/0030-poste-de-commande-versionne.md), [0031](done/0031-tests-hors-du-path-reel.md), [0032](done/0032-touchid-nomme-compte-et-produit.md), [0036](done/0036-admin-clarte-cartes-profil.md), [0037](done/0037-semantique-suppression-en-zone.md), [0040](done/0040-brancher-mcp-claude-code.md), [0041](done/0041-ecart-policy-surface-mcp.md), [0043](done/0043-lire-copier-televerser-drive-et-pj-gmail.md), [0044](done/0044-touchid-signe-nom-produit.md), [0047](done/0047-nommer-le-compte-au-moment-d-autoriser.md), [0059](done/0059-gwsa-resolve-folder-vault.md), [0061](done/0061-deconnexion-modale-confirmation.md), [0062](done/0062-admin-header-mode-avance.md), [0063](done/0063-tout-verrouiller-icone-modale.md), [0064](done/0064-bouton-retour-comptes.md), [0065](done/0065-masquer-connecter-compte-en-detail.md), [0066](done/0066-journal-lisibilite.md), [0067](done/0067-admin-branding-titre.md), [0068](done/0068-accessibilite-focus-reduced-motion.md), [0069](done/0069-docs-in-app-orientation-user.md), [0071](done/0071-github-metadata-topics.md), [0072](done/0072-site-doc-en-ligne.md), [0076](done/0076-droits-par-session-phase-a.md), [0078](done/0078-approbation-passkey-archi-actuelle.md), [0080](done/0080-durcir-capacites-fines-session.md), [0083](done/0083-durcir-approbation-passkey-distante.md), [0084](done/0084-durcir-consume-nonce-toctou.md), [0085](done/0085-figer-unlock-zones-sous-session.md), [0087](done/0087-install-branchement-clients-opt-in.md), [0088](done/0088-install-help-curl-pipe.md), [0095](done/0095-design-system-fondations-tokens.md), [0099](done/0099-sessions-pilote-tri-liste-vignettes.md), [0102](done/0102-journal-page-monitoring-filtres-par-session.md), [0103](done/0103-refonte-barre-navigation-admin.md), [0104](done/0104-app-shell-responsive-mobile.md), [0105](done/0105-refonte-admin-cockpit.md).
