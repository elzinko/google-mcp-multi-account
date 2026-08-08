---
id: 0074
title: Durcir la v1 — punch-list de lancement (doc, tests, hygiène)
type: feature
priority: P1
version: v1.0
epic:
status: todo
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

## Critères d'acceptation

### 🔴 Avant le tag v1 (doc)
- [ ] **`gws` rendu visible** (dépendance amont dure, aujourd'hui invisible) : étape 0
      `brew install …` dans le Quickstart README **et** `docs/index.md` ; absence
      rendue bloquante (`die`) ou affichée dans le pavé final d'`install.sh` ;
      **vérifier que le nom de formule résout** (sinon la seule instruction est fausse).
      *(install.sh:43-44, README.md:28-43, docs/index.md:40-56, mcp-setup.md:7)*
- [ ] **`critique.md` rafraîchi** (page publiée, liée 4×) : 17 tools (pas « 9 »),
      services Drive réels (read/update/copy/upload/permissions), limite
      « git clone / pas de release » recadrée en *historique*. Fix ciblé §4/§6, pas
      de réécriture. *(critique.md:76,99-100 vs gateway/mcp_server.py:53-394)*

### 🟠 À faire (avant de préférence, sinon juste après)
- [ ] **Collision d'id 0073** (#82 transfert Drive vs #86 pagination gmail_list) —
      renuméroter l'un vers un id libre. ⏳ **Time-sensitive** : tant que les 2 sont brouillons.
- [ ] **Tests admin anti-DNS-rebinding** : bad-Host + bad-Origin → 403 (2 `curl`,
      réutilise le node déjà démarré). *(admin/server.js:672,677 ; seul le no-header est testé, test.sh:2555)*
- [ ] **Test `DEFAULT_POLICY`** : invariants `send/delete/share=false`,
      `zonesOnly=true`, `writeFolders=[]` (+ le passer par `policy-check.py`).
      *(gateway/default_policy.py — 0 occurrence dans les tests)*
- [ ] **Diagramme mermaid du README corrigé** : `MCP→gateway→broker→gws→Google`,
      `gwsa` = porte humaine/admin. *(README.md:63-64 contredit architecture.md:104/205)*
- [ ] **Polish Quickstart** : étapes numérotées (1 install → 2 OAuth → 3 `gwsa add`
      → 4 redémarrer) ; alias unifié (`personal` README vs `perso` install.sh) ;
      « 3 minutes » → ~15 min ; définir `gws` vs `gwsa` dans le bloc Naming.
      *(README.md:36-41,93-97)*
- [ ] **Décompte de tools aligné dans `mcp-setup.md`** (17, ou renvoi au tableau).
      *(mcp-setup.md:67-70 vs :130-131)*

### 🟢 Confort (post-v1)
- [ ] Hygiène repo : supprimer les **13 branches distantes obsolètes** ; verrouiller
      « Squash and merge » comme seule stratégie.
- [ ] Durcissement latent : lier `payload.target` au hash du manifeste
      *(project.py:99-110)* ; borner la taille de `gmail_attachment_get`
      *(api.py:739-791)* ; documenter/sérialiser la course R-M-W de session
      *(sessions.py:165-173)* ; documenter dans SECURITY.md que
      `drive_permissions_create` + notification déclenche un **email Google**
      *(api.py:700)*.
- [ ] Couverture : `tools/call` bout-en-bout, `executor.py`/broker, strongauth réel
      (mock-only), `swiftc -parse` non gaté sur le label macos.
- [ ] Nettoyage admin : dead code `dUnlock`/`summary()` (~45 l), `const protected`→`isProtected`.
- [ ] Releases : backfill v0.1.0–v0.2.1 (ou tag = source de vérité assumée) ; date
      CHANGELOG v0.3.0 ; badge CI `?branch=main`.

## Notes

- **Anti-doublon** : les items ci-dessus sont majoritairement **nouveaux**. Ceux qui
  recoupent des fiches existantes y restent gérés, cette fiche les **cite sans dupliquer** :
  [[0028]] (`deploy-local.sh --prune`), [[0034]] (note « zone = territoire »),
  [[0039]] (bannir « jeton/token »), [[0067]] (branding titre admin — confirmé encore
  « gws multi-comptes — admin » sur `main` par screenshot du 2026-08-08).
- Source : rapport d'audit multi-agent v1 du 2026-08-08 (6 axes, 15 agents, 307 tests verts).
- **Gate** : critères concrets mais `ready:` non posé — passer `ready 0074` avant tirage.
