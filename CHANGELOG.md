# Journal des versions

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
