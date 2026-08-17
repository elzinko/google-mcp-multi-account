# Sprint — Droits par session, Phase A (fiche 0076)

Périmètre : implémentation Phase A desktop (POC cœur → complet) + docs au niveau existant.
Statut : en cours

## Backlog (1 ligne = 1 lot ; tout dans la PR #108 — 1 PR/fiche)

- [x] **POC cœur** — jeton porté dans l'appel + autorisation broker par jeton + abandon `set_session_id` global + cycle de vie (TTL/révocation ; la déconnexion MCP ne purge rien ; fix `last_seen` + GC)   ✅ commit `d693144`, `test.sh` 320 verts
- [x] Capacités fines signées — service×op×ressource ; élicitation signée EXIGÉE à chaque octroi ; intersection ∩ ; sans manifeste = policy ∩ session (+ anti-downgrade)   ✅ commit `203cc59`, `test.sh` 328 verts
- [x] `mag session list` + vue config · sous-agents · bootstrap sans jeton · audit des appels réussis   ✅ commit `72f858a`, `test.sh` 340 verts
- [!] **Collision gérée** : PR #108 (design+lot1) squash-mergée dans main par l'autre session (14:15). Branche rebasée sur main → reste = lot2+lot3 (+doc). Nouvelle PR à ouvrir.
- [x] **Doc** au niveau existant (architecture, policies, threat-model, SECURITY, glossaire)   ✅ commit `b1fe19d`
- [x] Gate locale verte (py_compile, bash -n, shellcheck, 340 tests, liens)   ✅
- [x] Revue `ezk-reviewer` : **NO-GO** (P0 fail-open Drive sur policy permissive) → **corrigé + testé** (`d6249a9`, +3 assertions, 343 verts)
- [x] Nouvelle PR d'implémentation **#110** (draft) sur `main`
- [ ] ⛳ **Checkpoint final** : feu vert humain pour merger (+ revue Codex ?)

Statut : **en attente de validation** — sprint livré, gate verte, revue traitée. Ne pas merger sans accord.
- [ ] Docs au niveau existant — architecture.md, policies.md, threat-model.md, SECURITY.md, glossaire ADR, README
- [ ] Gate locale (`scripts/test.sh` + ezk-ci) · revue `ezk-reviewer` · MAJ PR #108

## Definition of Done

Critères d'acceptation de la fiche 0076 verts (assertions `scripts/test.sh`) • `scripts/test.sh` vert • ezk-ci (act+Docker) vert • revue GO (code + sécu) • docs à jour au niveau existant • PR #108 relisable seule.

## Notes / décisions

- **1 PR/fiche** : implémentation sur la branche existante (`claude/session-limited-access-rights-76b457`, PR #108), pas de nouvelle branche — le design y est déjà.
- Archi **figée** : ADR-0007 (15 findings Codex traités).
- Tests = **assertions bash hermétiques** dans `scripts/test.sh` (`policy-check.py` + `bin/mag`, `GWSA_ROOT` temp, `GWSA_ELICITATION_MOCK=1`).
- Phases B/C = axe **mobile souverain** (ADR-0008 / PR #109) — hors périmètre.
