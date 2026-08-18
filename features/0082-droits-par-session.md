---
id: 0082
title: Droits par session — isolation & capacités fines par conversation
type: epic
priority: P1
version:
epic:
status: in-progress
ready:
pr:
created: 2026-08-17
---

## En clair

**Épic parapluie** de l'axe « droits par session » : donner à **chaque conversation
LLM son propre périmètre d'accès** Google (compte × service × opération × ressource),
isolé des autres sessions du poste, signé et expirant. **Aucun travail propre** — il
coordonne ses enfants et n'est **jamais tirable**. État : la Phase A desktop
([0076](done/0076-droits-par-session-phase-a.md), livrée #108/#110) est faite ;
restent l'analyse ([0045](0045-capacites-projet-signees.md), en cours) et le
durcissement ([0080](0080-durcir-capacites-fines-session.md)).

## Contexte / Problème

**Avant la Phase A** ([0076](done/0076-droits-par-session-phase-a.md), livrée #108/#110),
les autorisations d'accès aux comptes Google étaient **globales au poste** : un `unlock`
de compte ou un `grant` de zone Drive profitait à **toutes** les conversations LLM
ouvertes en parallèle. La Phase A a **inversé** ce défaut — chaque conversation **repart
de zéro**, avec des capacités propres, fines, signées et révocables, sans que l'agent
puisse s'auto-attribuer des droits (cf. `SECURITY.md`, `docs/policies.md`). Un `unlock`
de compte hérité peut rester machine-wide, mais il ne donne plus à une conversation
l'accès aux **données** sans ses propres capacités de session. Reste à **durcir** cette
couche ([0080](0080-durcir-capacites-fines-session.md)).

Cet axe rassemblait ses fiches par une chaîne `epic:` feature→feature (0080→0076→0045),
seul thème multi-fiches du backlog sans épic ombrelle — d'où deux warnings d'intégrité
au `regen` (ADR-0017 : `epic:` doit pointer un `type: epic`). Cet épic fournit
l'**ombrelle unique**, sans rien changer au code déjà livré.

Décision d'architecture fondatrice :
**[ADR-0007](../docs/adr/ADR-0007-droits-par-session.md)** — identité par geste de
consentement signé, jeton porté dans l'appel, cycle de vie découplé de la connexion MCP.

## Proposition

Épic parapluie qui **regroupe** les incréments menant aux droits par session. **Aucun
travail propre : il coordonne ses enfants. Jamais tirable.**

Enfants :
- **[0045](0045-capacites-projet-signees.md)** — état des lieux, écarts, pistes (spike
  d'analyse ; garde son contenu propre, **non promu** en épic).
- **[0076](done/0076-droits-par-session-phase-a.md)** — Phase A desktop : identité par
  consentement, jeton porté, capacités fines signées (**livré**, #108/#110).
- **[0080](0080-durcir-capacites-fines-session.md)** — durcir la couche capacités fines
  (ressource hors-Drive, capacités déléguées figées, audit aligné) — suite revue Codex #110.

## Critères d'acceptation

- [ ] Les fiches de l'axe (0045, 0076, 0080) portent `epic: 0082` — chaîne `epic:`
      cohérente (ADR-0017).
- [ ] `regen` n'émet **plus** de warning d'intégrité sur cet axe.
- [ ] Épic sans critère de livraison propre : clos quand ses enfants actionnables
      (0045, 0080) sont livrés ou archivés (0076 déjà livré).

## Comment vérifier

- `/ezk-backlog regen` (script `regen-backlog.sh`) ne signale **aucun** warning
  d'intégrité sur cet axe (plus de `epic: … introuvable ou non-epic` pour 0076/0080).
- Dans `features/BACKLOG.md` (section « 🧭 Épics »), l'épic **0082** apparaît ;
  0045/0076/0080 affichent `0082` en colonne Épic.

## Notes

- **Statut `in-progress`** : la Phase A (0076) est déjà livrée — l'axe est en cours,
  pas au repos.
- **Priorité P1** : alignée sur l'enfant actif le plus urgent (0080) et la nature
  stratégique de l'axe (ADR-0007).
- **Épic frère : [0077](0077-acces-mobile-souverain.md)** (Accès mobile souverain,
  ADR-0008). Deux épics **frères**, pas parent/enfant (ADR-0017 : 2 niveaux max, pas
  d'épic → épic). #108 isole le périmètre par *session* (couche desktop) ; 0077 apporte
  le *consentement mobile* (passkey) + le *holder*. La phase 1 de 0077 (0078) est la
  « phase B » de cet axe — une seule conception, pas deux.
