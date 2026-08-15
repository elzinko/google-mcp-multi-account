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

1. **Identité par geste de consentement** (local desktop, signé via ADR-0005) au lieu
   de l'`initialize`.
2. **Jeton de session porté dans chaque appel** (paramètre sur les tools ; autorisation
   broker par jeton) → deux conversations d'une **même connexion** Desktop sont isolées.
3. **Config fine par session** : (compte, **service × opération × ressource**),
   expirante ; droits effectifs = policy ∩ manifeste ∩ session.
4. **`gma session list`** + vue de la config par session.
5. **Corriger** : purge en fin de session + TTL réel ; `last_seen` mis à jour à chaque
   appel.

Hors périmètre (phases suivantes) : consentement distant desktop↔Android (0077),
hôte Android pour desktop éteint (0078).

## Critères d'acceptation

- [ ] Deux sessions sur **la même connexion MCP** ont des droits distincts (jeton porté),
      vérifié par un test hermétique.
- [ ] Une nouvelle session **sans geste** = **zéro droit** (default-deny).
- [ ] La config d'une session s'exprime au grain **service × opération × ressource**
      (ex. `perso gmail:read`, `perso drive:write:<zone>`).
- [ ] `gma session list` liste les sessions actives et **affiche la config de chacune**.
- [ ] Fin de session (déconnexion MCP) → registre **purgé** ; TTL d'inactivité effectif ;
      `last_seen_at` avance à chaque appel.
- [ ] Jeton absent / invalide / expiré → **refus** journalisé.
- [ ] `./scripts/test.sh` vert (tests hermétiques, sans comptes réels).

## Notes

- Parent / état des lieux : [0045](0045-capacites-projet-signees.md).
- Élicitation signée réutilisée : [ADR-0005](../docs/adr/ADR-0005-elicitation-signee-v2.md)
  / fiche [0001](0001-elicitation-signee-strongauth-v2.md).
- Phases suivantes : consentement distant (0077), hôte Android (0078) — ce dernier
  **conditionné au vault** [0003](0003-vault-credentials-hors-perimetre-agent.md).
- Décisions de cadrage (14/08) : identité = geste de consentement ; granularité la plus
  fine ; mobile = hôte **et** dispositif de consentement selon la topologie.
