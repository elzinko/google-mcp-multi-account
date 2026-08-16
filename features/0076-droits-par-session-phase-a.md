---
id: 0076
title: Droits par session (Phase A desktop) — identité par consentement, jeton porté, config fine
type: feature
priority: P2
version:
epic: 0045
status: todo
ready:
pr:
created: 2026-08-15
---

## Contexte / Problème

La fiche [0045](0045-capacites-projet-signees.md) vise l'isolation par session ; le
code existe (`gateway/sessions.py`, registre `.sessions/`, `gma session …`) mais est
**branché à vide**. Concrètement, sur un Desktop toujours allumé :

- une seule connexion MCP → un seul `session_id` (posé en **global** à l'`initialize`,
  `gateway/context.py`) → **toutes les conversations partagent les mêmes droits** ;
- les droits sont **grossiers** (unlock compte + zones Drive), pas de grain
  service / opération / ressource ;
- le registre `.sessions/` **fuit** (pas de purge) et `last_seen_at` est **figé**
  (TTL d'inactivité mort) — constaté sur 7 sessions du poste le 14/08.

Décision d'architecture : [ADR-0007](../docs/adr/ADR-0007-droits-par-session.md).

## Proposition (Phase A — desktop seul)

1. **Identité par geste de consentement** (local desktop, signé via ADR-0005 — **exigé pour toute session**, indépendamment du flag `.strong-auth` global ; enrôlement requis) au lieu
   de l'`initialize`.
2. **Jeton de session porté dans chaque appel** (paramètre sur les tools ; autorisation
   broker par jeton) → deux conversations d'une **même connexion** Desktop sont isolées.
3. **Config fine par session** : (compte, **service × opération × ressource**),
   expirante ; **chaque octroi de capacité est signé** (création *et* élargissement),
   indépendamment de `.strong-auth` ; droits effectifs = policy ∩ manifeste ∩ session
   (sans manifeste projet valide : `policy ∩ session` — le manifeste est un plafond
   *optionnel*, jamais un déni).
4. **`gma session list`** + vue de la config par session.
5. **Corriger** : cycle de vie **découplé de la connexion** (TTL réel + `gma session close`/révocation ; une déconnexion de connexion *partagée* ne purge pas les jetons des autres conversations) ; `last_seen` mis à jour à chaque
   appel.

Hors périmètre (phases suivantes) : consentement distant desktop↔Android (0077),
hôte Android pour desktop éteint (0078).

## Critères d'acceptation

- [ ] Deux sessions sur **la même connexion MCP** ont des droits distincts (jeton porté),
      vérifié par un test hermétique.
- [ ] **Création de session = geste signé exigé** (enrôlement requis) ; sans enrôlement → **refus** (`gma elicitation enroll`), indépendamment du flag `.strong-auth`.
- [ ] **Toute mutation de capacité** (unlock, grant fin) exige une **signature liant le scope exact** (compte / service / op / ressource) — **testée** —, indépendamment de `.strong-auth` ; **pas d'élargissement non signé** jusqu'aux plafonds compte / projet.
- [ ] Une **session racine** ne peut **pas exister sans geste signé** (refus — cf. critère de création) ; une session fraîchement créée = **zéro capacité** tant qu'aucun octroi signé ; une **sous-session déléguée** (`parent_session_id`) hérite d'un **sous-ensemble** du parent, sans geste propre.
- [ ] **Sous-agents** : héritage ⊆ parent, **pas d'`access_request`/élargissement** depuis un enfant, **révocation en cascade** depuis la racine (aligne fiche [0045](0045-capacites-projet-signees.md) §683-685) — inheritance/revocation **testés**.
- [ ] La config d'une session s'exprime au grain **service × opération × ressource**
      (ex. `perso gmail:read`, `perso drive:write:<zone>`).
- [ ] **Ressource propre au service et optionnelle** : Drive = dossier/zone (exigée en
      écriture), Gmail = label (optionnel), Calendar = agenda (optionnel) ; ressource
      absente = périmètre service **borné par la policy** (jamais au-delà) — spécifié + **testé**.
- [ ] **Bootstrap sans jeton** : un appel sans jeton ne peut **que** déclencher
      l'élicitation signée de création (`gma session open` / `access_request`) ; **aucun
      accès données** sans jeton ; le jeton n'est délivré **qu'après** élicitation signée réussie — **testé**.
- [ ] `gma session list` liste les sessions actives et **affiche la config de chacune**.
- [ ] Cycle de vie **découplé de la connexion** : fin par **TTL** ou **`gma session close`/révocation** → registre purgé ; sur une connexion *partagée*, la déconnexion **ne supprime pas** les jetons des autres conversations ;
      `last_seen_at` avance à chaque appel.
- [ ] Jeton absent / invalide / expiré → **refus** journalisé.
- [ ] **Appels réussis journalisés** avec `session_id` + service / opération / ressource (pas seulement les refus) — **testé** (M-08 / ADR-0007).
- [ ] **Sans manifeste projet valide** (hors dépôt git / repo non signé) : droits effectifs = `policy ∩ session` (plafond projet **omis**, jamais un déni) — cas **testé**.
- [ ] `./scripts/test.sh` vert (tests hermétiques, sans comptes réels).

## Notes

- Parent / état des lieux : [0045](0045-capacites-projet-signees.md).
- Élicitation signée réutilisée : [ADR-0005](../docs/adr/ADR-0005-elicitation-signee-v2.md)
  / fiche [0001](0001-elicitation-signee-strongauth-v2.md).
- Phases suivantes : consentement distant (0077), hôte Android (0078) — ce dernier
  **conditionné au vault** [0003](0003-vault-credentials-hors-perimetre-agent.md).
- Décisions de cadrage (14/08) : identité = geste de consentement ; granularité la plus
  fine ; mobile = hôte **et** dispositif de consentement selon la topologie.
- Retours **Codex** ([PR #108](https://github.com/elzinko/google-mcp-multi-account/pull/108)) intégrés : cycle de vie découplé de la connexion MCP (①) ; **création de session sous élicitation signée exigée** (②) ; **chaque octroi de capacité signé, pas seulement la création** (③) ; **héritage sous-agents ⊆ parent préservé** (④) ; ADR ajouté à la nav MkDocs (⑤) ; critères 0045 périmés marqués remplacés (⑥) ; racine non signée refusée (⑦) ; audit des appels réussis couvert (⑧) ; TGT-04 de 0045 corrigé (⑨) ; intersection sans manifeste = `policy ∩ session` (⑩) ; bootstrap sans jeton défini (⑪) ; ressource propre au service, optionnelle (⑫) ; supersedance globale de 0045 (⑬).
