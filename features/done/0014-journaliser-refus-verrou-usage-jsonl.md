---
id: 0014
title: Journaliser les refus de verrou dans usage.jsonl (decision:refus, reason:locked)
type: bug
priority: P1
version:
epic:
status: shipped
ready: 2026-07-24
pr: "#17"
created: 2026-07-24
---

## Contexte / Problème

Le journal d'audit `~/.config/gws-accounts/usage.jsonl` trace les appels
autorisés (`scripts/log-usage.py`, `decision:ok`) et les refus de policy
(`scripts/policy-check.py::deny`, `decision:refus`) — mais **jamais les refus
pour verrou**. Trois chemins sortent avant toute journalisation :

1. `bin/gwsa` : `die` sur `is_locked` **avant** l'appel au `USAGE_LOGGER` ;
2. `gateway/broker_server.py::handle_exec` : `GatewayError` code `locked` via
   `require_unlocked`, avant `check_policy` / journalisation ;
3. `gateway/api.py::_run` : fail-fast `require_unlocked` local — le broker ne
   voit même pas l'appel, donc rien n'est tracé nulle part.

Conséquence : l'audit ne voit pas qu'un agent a **tenté** d'accéder à un profil
verrouillé — précisément le signal que le verrou « accès sur demande » est censé
rendre observable. SECURITY.md (PR #16) documente honnêtement cette lacune.

## Proposition

Écrire une ligne `decision:refus, reason:locked` (avec `client` = `GWSA_CLIENT`)
sur les trois chemins, en réutilisant le logger existant :

- `scripts/log-usage.py` : décision/raison surchargeables par environnement
  (`GWSA_LOG_DECISION`, `GWSA_LOG_REASON`) — défaut `ok`, appelants existants
  inchangés ;
- `bin/gwsa` : journaliser avant le `die` du verrou ;
- `gateway/usage.py` (nouveau) : helper partagé `log_usage(…, decision, reason)`
  (remplace `log_ok` du broker) ; le broker et le fail-fast de `api._run`
  journalisent le refus `locked` avant de relever l'erreur.

Pas de double ligne : quand le fail-fast gateway refuse, le broker n'est jamais
appelé ; quand le broker refuse, il est le seul à tracer.

## Critères d'acceptation

- [x] `gwsa <alias> …` sur profil verrouillé → 1 ligne `decision:refus,
      reason:locked` dans `usage.jsonl` (alias, cmd, client) avant l'erreur.
- [x] Refus `locked` du broker (RPC **et** `handle_exec` direct) → même ligne.
- [x] Refus fail-fast de `gateway/api._run` → même ligne, client = `client_id()`.
- [x] Les appels autorisés et les refus de policy restent journalisés comme avant.
- [x] Tests hermétiques dans `scripts/test.sh` couvrant les trois chemins
      (GWSA_ROOT temporaire, aucun compte réel).
- [ ] SECURITY.md ne mentionne plus la lacune (suivi : la phrase arrive avec la
      PR #16, encore ouverte — à retirer après le merge des deux PRs).

## Notes

- La journalisation est best-effort (jamais bloquante, comme `log_ok` avant) :
  un échec d'écriture du journal n'empêche pas le refus de se produire.
- `require_unlocked` lève aussi `not_found` / `alias` : non journalisés — seul
  le refus de **verrou** est un événement d'audit (tentative sur profil fermé).
- docs mis à jour : `docs/threat-model.md` (§ Journal d'audit) et
  `docs/architecture.md` (carte des contrôles).
