---
id: 0074
title: Durcir la v1 — punch-list de lancement (doc, tests, hygiène)
type: feature
priority: P1
version: v1.0
epic:
status: in-progress
ready:
pr:
created: 2026-08-08
---

## Contexte / Problème

Audit critique **multi-agent** du 2026-08-08 (6 axes : hygiène PR/branches/backlog,
tests, doc onboarding, admin, README+releases, code cœur ; chaque bloquant
reconfirmé par un agent adverse). **Verdict : la v1 est très proche** — **307 tests
verts, zéro bug vivant, posture sécurité correcte au runtime**. Le code n'est pas
le problème. Restent des correctifs de **qualité de lancement** (doc + couverture
de tests + hygiène), tous bon marché. Cette fiche les regroupe pour tirer la v1.

> **Volet DOC livré** par la PR `docs/0074-v1-doc-blockers` (2026-08-08) — cases
> cochées ci-dessous. Restent les volets **tests** et **hygiène/code** (à faire hors
> de cette PR doc-only).

## Critères d'acceptation

### 🔴 Avant le tag v1 (doc)
- [x] **`gws` rendu visible** dans la doc : prérequis `brew install googleworkspace-cli`
      ([`googleworkspace/cli`](https://github.com/googleworkspace/cli), commande
      confirmée côté upstream) en tête du Quickstart README + docs/index.md + mcp-setup.md.
- [ ] **`gws` durci côté `install.sh`** : préflight `command -v gws` bloquant (`die`)
      ou affiché dans le pavé final — *reste à faire (touche l'installeur, hors PR doc)*.
- [x] **`critique.md` rafraîchi** : 17 tools (plus « 9 »), services Drive réels,
      « git clone / pas de release » recadré (curl + releases + `gwsa update`).

### 🟠 À faire
- [x] **Diagramme mermaid du README corrigé** : `MCP→gateway→Google`, `gwsa` = porte
      humaine/admin (ne route plus le MCP par `gwsa`).
- [x] **Décompte de tools aligné dans `mcp-setup.md`** (17).
- [x] **Polish Quickstart** : étapes numérotées, `gws` vs `gwsa` défini (bloc Naming),
      timing corrigé (~10 min OAuth, plus de « 3 minutes »), alias `perso` unifié
      README ↔ docs.
- [ ] **Collision d'id 0073** (#82 transfert Drive vs #86 pagination gmail_list) —
      renuméroter l'un. ⏳ **Time-sensitive** tant que les 2 sont brouillons.
- [ ] **Tests admin anti-DNS-rebinding** : bad-Host + bad-Origin → 403.
      *(admin/server.js:672,677 ; seul le no-header est testé)*
- [ ] **Test `DEFAULT_POLICY`** : invariants `send/delete/share=false`,
      `zonesOnly=true`, `writeFolders=[]` (+ via `policy-check.py`).
      *(gateway/default_policy.py — 0 occurrence dans les tests)*

### 🟢 Confort (post-v1)
- [ ] Hygiène repo : supprimer les **13 branches distantes obsolètes** ; verrouiller
      « Squash and merge ».
- [ ] Durcissement latent : lier `payload.target` au hash du manifeste
      *(project.py)* ; borner `gmail_attachment_get` *(api.py)* ; sérialiser la
      course R-M-W de session *(sessions.py)* ; documenter l'email Google de
      `drive_permissions_create` *(SECURITY.md)*.
- [ ] Couverture : `tools/call` bout-en-bout, `executor.py`/broker, strongauth réel.
- [ ] Nettoyage admin : dead code `dUnlock`/`summary()` (~45 l), `const protected`→`isProtected`.
- [ ] Releases : backfill v0.1.0–v0.2.1 (ou tag = source de vérité) ; date CHANGELOG v0.3.0 ;
      badge CI `?branch=main`.

## Notes

- **Anti-doublon** : les items sont majoritairement **nouveaux**. Ceux qui recoupent
  des fiches existantes y restent gérés, cette fiche les **cite sans dupliquer** :
  [[0028]] (`--prune`), [[0034]] (« zone = territoire »), [[0039]] (bannir « jeton »),
  [[0067]] (branding titre admin — confirmé encore « gws multi-comptes — admin » sur
  `main` par screenshot du 2026-08-08).
- Source : rapport d'audit multi-agent v1 du 2026-08-08 (6 axes, 15 agents, 307 tests verts).
- **Gate** : critères concrets mais `ready:` non posé — passer `ready 0074` avant de
  tirer les volets restants.
