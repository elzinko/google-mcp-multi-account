# Journal des versions

## v1.1.0 — 2026-08-29

### Fonctionnalités

- feat(install): brancher les clients LLM en opt-in, pas opt-out (#123)
- feat(0085): figer unlock + zones Drive à la création d'une sous-session (isolation complète) (#119)
- feat(0080): durcir la couche capacités fines de session (suite revue Codex #110) (#118)
- feat(0078): approbation par passkey distante depuis le téléphone (POC holder Mac) (#113)
- feat(admin): reprise UX refresh admin (épic 0060) — split propre de #84 (#112)
- feat(0076): droits par session — implémentation Phase A (jeton porté, capacités fines signées)

### Corrections

- fix(remote_approval): verrou partagé inter-process contre le TOCTOU anti-clonage sign_count (#126)
- fix(elicitation): verrou inter-process sur consume_nonce contre une course TOCTOU (#125)
- fix(install): aide --help robuste sous « curl | bash » (#124)
- fix(security): borne la taille des pièces jointes Gmail + doc partage/PJ (fiche 0074) (#107)
- fix(install): préflight « gws » bloquant + commande copiable (fiche 0074) (#106)

### Documentation

- docs(nav): raccourcir « Prérequis — OAuth / Google Cloud » en « Prérequis »
- docs: ajoute ALTERNATIVES.md (projets similaires / veille)
- docs(backlog): fiches 0089-0093 — profil OAuth, statut OAuth, DX updater, bascule gwsa→mag, cohérence nommage
- docs(backlog): ship 0083 (verrou anti-clonage sign_count) — PR #126 → done/
- docs: règle d'écriture claire (En clair d'abord)
- docs(backlog): ship 0084 (verrou consume_nonce TOCTOU) — PR #125 → done/
- docs: références fiches en chemins locaux, pas d'URL GitHub (fix mkdocs --strict) (#122)
- docs(backlog): ship 0088 (aide install.sh robuste curl|bash) — PR #124 → done/
- docs(backlog): ship 0087 (installeur opt-in) — PR #123 → done/
- docs: aligner README + cartes index sur le split CLI / Admin web (#120) (#121)
- docs: toilettage du site — nav (policy→Sécurité, CLI/Admin), mag help, cartes cliquables, wording clients (#120)
- docs(backlog): fiche 0087 — brancher les clients LLM en opt-in dans install.sh
- docs(backlog): ship 0085 (figer unlock+zones à la création de sous-session) — PR #119 → done/
- docs(backlog): normaliser pr: de 0080 en guillemets doubles (#118 dans l'index)
- docs(backlog): ship 0080 (durcir capacités fines de session) — PR #118 → done/
- docs(backlog): fiche 0086 — raffinements audit + migration capacités session (suite revue #118)
- docs(backlog): fiche 0085 — figer unlock+zones à la création de sous-session (finding revue 0080)
- docs(backlog): tampon ready sur 0080 (concurrence ezk-pm) — 1er sprint du build
- docs(backlog): fiches 0083 (passkey) + 0084 (consume_nonce TOCTOU) + migration Skema v2 (#115)
- docs(backlog): épic ombrelle 0082 « droits par session » (rattache 0045/0076/0080) (#117)
- docs(backlog): ship épic 0060 — fiches 0061-0069 → done/ (#112) (#116)
- docs(backlog): fiche 0078 livrée (shipped, PR #113) → done/
- docs(sessions): archive session 2026-08-16 droits-par-session-0076
- docs(backlog): classe la fiche 0076 en done/ (shipped #110)
- docs(0076): fiche droits par session livrée (shipped, PR #110) (#111)
- docs(archi): accès mobile souverain — ADR-0008 + comparateur + épic 0077/0078 (#109)
- docs(0076): droits par session — ADR-0007 + fiche Phase A (#108)
- docs: unifie l'install par client (page Configurer) + OAuth en préalable + gwsa→gma (#105)

### Autres

- chore: gitignore .vercel/ (artefact CLI Vercel)
- chore(cli): renommer la commande gma → mag (collision oh-my-zsh) (#114)
- chore(deps): bump actions/setup-python from 5 to 7 (#104)
- chore(deps): bump actions/configure-pages from 5 to 6 (#103)
- chore(deps): bump actions/checkout from 4 to 7 (#102)
- chore(deps): bump actions/deploy-pages from 4 to 5 (#101)
- chore(deps): bump actions/upload-pages-artifact from 3 to 5 (#100)

## v1.0.1 — 2026-08-09

### Corrections

- fix(install): préflight gws + récap gma/email + github.io only

### Documentation

- docs(adr): rampe nouveau venu — glossaire curé + TL;DR (compréhensible)
- docs(features): 0074 — note de clôture v1.0.0

## v1.0.0 — 2026-08-09

### Fonctionnalités

- feat(cli): gma wire <client> — brancher un client MCP en une commande
- feat(cli): désigner un compte par son email (alias = raccourci optionnel)
- feat(cli): renommer gwsa → gma (alias déprécié conservé)

### Documentation

- docs: refonte pro — threat-model + policies contextualisés + page Contribuer
- docs: refonte modèle — Prise en main (tuto) + architecture réécrite
- docs: pré-v1 — gws, critique.md, Quickstart, mermaid, gwsa, déploiement Pages (0074)
- docs(site): expliquer les deux noms (dépôt vs connecteur MCP)
- docs(site): accentuer les titres de catégories du menu
- docs(site): liens source en URLs GitHub absolues + ADRs dans la nav

### Autres

- test(security): garde admin (DNS-rebinding + Origin) + invariants DEFAULT_POLICY
- chore(features): passe reconcile+review — ship 3, dédoublonner, rescope 6 (#88)

## v0.4.0 — 2026-08-04

### Fonctionnalités

- feat(drive): grant par nom (vault) + drive_update + partage lecture/écriture (#77)
- feat(docs): site de doc en ligne MkDocs Material (#79)
- feat(install): installer & mettre à jour sans clone — curl + tarball GitHub (#78)
- feat: rebrand to google-multi-account + English-first landing & README (#58)
- feat(elicitation): nommer le compte (email) au moment d'autoriser — fiche 0047 (#75)
- feat(0043): lire, copier et téléverser Drive + pièces jointes Gmail via MCP (#73)

### Corrections

- fix(elicitation): dialogue Touch ID strongauth nomme le produit (#74)
- fix(docs): clarifier policy admin ≠ surface MCP (fiche 0041) (#52)

### Documentation

- docs(readme): quickstart mène avec l'install curl (sans clone)
- docs(features): ship 0059 (#77) — grant par nom via vault
- docs(features): ship 0020 (#78) + 0072 (#79)
- docs(features): add 0059 vault folder resolve bug + manual test
- docs(features): add v0.4.0 Admin UX epic 0060 and children 0061–0071
- docs(features): ship 0047 #75
- docs(features): ship 0044 #74

### Autres

- chore(backlog): ship 0043
- chore(backlog): résout collisions d'id 0040/0041 (→0045/0046)
- chore(deps): bump actions/checkout from 4 to 7 (#55)
- chore(security): enable Dependabot config and document GitHub security (#53)

## v0.3.0 — 2026-07-29

### Fonctionnalités

- feat(cli): gwsa session/project/sandbox commands and hermetic tests
- feat(admin): Dev panel, sessions UI, and MCP entry removal
- feat(sandbox): deploy CLI with wire/remove and detached HEAD fix
- feat(0040): MCP sessions, project manifest, and policy caps
- feat(0001): signed elicitation and vault credentials path
- feat(admin): lock chip, relock modal, and Touch ID UX
- feat(gwsa): dev corridors, isolated OAuth seed, and dev test
- feat(admin): zones folder picker and authorize flow
- feat(policy): corbeille = suppression + racine de zone immuable (fiche 0037)
- feat(deploy): brancher le MCP dans Claude Code (CLI), pas seulement Desktop (fiche 0040)
- feat(admin): refonte des cartes profil admin — liste → page de détail (fiche 0036)

### Corrections

- fix(vault): honor Codex review on credentials and session unlock
- fix(gwsa): exiger l'email sur add sous strongauth (0032)
- fix(admin): keep Touch ID unlock/grant from dropping the HTTP connection
- fix(admin): keep policy actions visible and drop duplicate Zones button
- fix(gwsa): fiabiliser dev test CI et broker hermétique

### Documentation

- docs(features): ship 0027 + 0032 après PR #48 (#50)
- docs(features): statut shipped effectif sur 0037 (rattrapage)
- docs(features): ship 0037 (#47)
- docs(features): statut shipped effectif sur 0036/0040 (rattrapage du ship)
- docs(features): ship 0036 (#44) + 0040 (#43)
- docs(design): maquette v11 (interrupteur + cadenas-bouton) ; fiche 0036 = spec
- docs(design): maquette v10 admin (lexique sans plomberie) + fiche 0039
- docs(design): maquette v9 admin (emplacement d'ajout de zone en pointillés)
- docs(design): maquette v8 admin (zones resserrées, ajout multi-zones)
- docs(design): maquette v7 admin (liste → détail) + note ADR-0004
- docs(design): maquette v6 des cartes admin (fenêtre zones + navigateur Drive)
- docs(design): maquette v5 des cartes admin (droits par appli, zones sous Drive)
- docs(design): maquette v4 des cartes admin (copie par le nom, modale d'ajout)
- docs(design): maquette v3 des cartes admin (alias retirés, état reformulé)
- docs(design): maquette v2 des cartes admin + ADR-0004 (proposé)
- docs(design): maquette v1 des cartes profil de l'admin (revue UX)
- docs(features): ferme 0033, ouvre 0037 (suppression en zone) + 0038 (créer dossier-zone)
- docs(features): add 0035 (acces rapide admin) + 0036 (clarte cartes profil)
- docs(features): add 0032-0034 (touchid nomme le compte, grant one-shot, maj protocole test)

### Autres

- test(ci): couvrir gwsa dev isolé, use --apply et list/status/remove

## v0.2.1 — 2026-07-27

### Corrections

- fix(tests): la suite ne peut plus toucher le gwsa du PATH reel (fiche 0031)

### Documentation

- docs(features): ship 0031 #31
- docs(features): 0031 en cours sur #31
- docs(features): add 0031 tests hors du PATH reel

## v0.2.0 — 2026-07-27

### Fonctionnalités

- feat(cli): gwsa update / release, et le PATH suit la version installee (fiche 0030)
- feat(release): publier et mettre a jour en une commande (fiche 0029)

### Documentation

- docs(features): ship 0029 #28 et 0030 #30
- docs(features): 0030 sur #30 (la #29 a ete fermee avec sa branche de base)
- docs(features): 0030 en cours sur #29
- docs(features): add 0030 poste de commande versionne
- docs(readme): installer via update.sh + section Versions (fiche 0029)
- docs(features): 0029 en cours sur #28
- docs(features): add 0029 release et update en une commande

## v0.1.1 — 2026-07-26

### Corrections

- fix(mcp): un broker par couloir, port ecrit dans l'entree MCP (fiche 0025)

### Documentation

- docs(features): ship 0025 #27
- docs(features): 0025 en cours sur #27
- docs(features): add 0025 couloirs etanches + 0026-0028 idees

## v0.1.0 — 2026-07-26

### Fonctionnalités

- feat(deploy): deployer le MCP en local, decouple du code de travail (fiche 0023)
- feat(profils): email = métadonnée persistée (.email) — zéro exécution gws hors broker (#18)
- feat(setup): brancher Claude Desktop en un geste (script idempotent) (#15)
- feat(admin): panneau Santé du setup + bouton Réparer l'accès IAM (fiche 0012)
- feat(mcp): tool setup_status (lecture seule) + provision-gcp.sh status --json
- feat(admin): doc intégrée à jour — onglets Schémas (mermaid local) et MCP & tools
- feat(gwsa): sous-commande `admin` — l'interface web en un geste, citée par l'élicitation
- feat(gwsa): strongauth (Touch ID) exigée sur `add` quand elle est activée
- feat(gateway): access_request kind=add_account — connexion de compte élicitée
- feat(provision): sous-commande sync-iam idempotente + publication mémorisée
- feat(provision): `status` signale les comptes connectés sans rôle IAM
- feat(gwsa): sonde IAM après `add` — surface le 403 quota project tôt
- feat(iam): détecteur hermétique du 403 « quota project » + remédiation
- feat(tests): tests manuels E2E multi-comptes + onboarding IAM + backlog suivi
- feat: Phase 2A local broker — gws only behind loopback RPC
- feat: add local MCP gateway with default-deny policies
- feat: accès multi-comptes Google pour agents LLM, 100 % local

### Corrections

- fix(mcp): brouillon Gmail casse, Drive sans contenu ni proprietaire (fiche 0024)
- fix(journal): journaliser les refus de verrou dans usage.jsonl (fiche 0014) (#17)
- fix(admin): ne pas exposer un compte réel dans les exemples du formulaire

### Documentation

- docs(features): ship 0024 #26
- docs(features): 0024 en cours sur #26
- docs(features): add 0024 fiabiliser les tools Gmail/Drive du MCP
- docs(features): ship 0023 #25
- docs(features): ready 0023
- docs(features): groom 0023 vers la DoR
- docs(features): add 0023 versionner-deployer-mcp-local
- docs(features): groom 0018 et repasser en P3 (ouverte aux contributions)
- docs(features): ship 0022 (#23)
- docs(gwsa): corriger le commentaire sur les scopes restreints
- docs: critique technique + backlog de généralisation (fiches 0017-0022)
- docs: réconcilier l'après-#16/#17/#18 (SECURITY.md + fiche 0016)
- docs: ajouter un regard critique du projet (docs/critique.md)
- docs(features): ship 0014 (#17)
- docs(readme): quickstart copiable, badges, SECURITY.md et licence MIT (#16)
- docs(features): ship 0013 (#15)
- docs(backlog): ship 0010 (#13) et 0012 (#14)
- docs(readme): refonte en quickstart 3 étapes (fiche 0010)
- docs(backlog): ship 0002 (#12) — default-deny vérifié et verrouillé par tests
- docs(backlog): ship 0009 (#11) — tool setup_status
- docs(backlog): cleanup — ship 0004 (broker, 12114ac) + 0002 point 2 résolu, P3→P2
- docs(features): ship 0005 (#5) 0007 (#10) 0008 (#7) 0011 (#9) + ADR-0001 accepté
- docs(features): 0011 — critère doc intégrée (Schémas + MCP) coché
- docs(features): 0009 — note démarrage admin (manuel vs launchd, jamais via le process MCP)
- docs: README relié aux diagrammes + table des tools MCP par groupe
- docs(diagram): lecture-donnees-elicitee — verrou, unlock élicité, lecture sous policy
- docs(adr): ADR-0001 onboarding par élicitation + fiches 0009/0010
- docs(diagram): onboarding — 3 séquences (setup initial, add_account élicité, réparation IAM)
- docs(features): 0008 → in-progress, critères cochés + règle CLAUDE.md
- docs(features): 0007 → in-progress, critères cochés + doc sync-iam
- docs(features): 0005 → in-progress + doc de l'outillage IAM
- docs: add architecture reference for Phase 1 security controls

### Autres

- chore: ignore .claude/handoff.md (note de clôture ezk-archive, éphémère)
- test(policy): verrouille le default-deny sur toute la classe de services
- test: add_account couvert — élicitation sans création + enum MCP
- test: cas hermétique du détecteur IAM (403 quota project)
- refactor: remove dead gateway/policy.py
