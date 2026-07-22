---
id: 0004
title: Broker daemon local Phase 2 A — gws derrière socket loopback
type: feature
priority: P1
version:
epic:
status: shipped
ready: 2026-07-21
pr: "12114ac"
created: 2026-07-21
---

## Contexte / Problème

Phase 1 : MCP + gateway appellent `gws` dans le même process / même périmètre
filesystem que l’agent. Un shell libre contourne policy/lock. On veut une
**porte unique** (broker) rapidement, sans vault (→ fiche 0003).

## Proposition

- Daemon local `bin/google-broker` (127.0.0.1 ou Unix socket).
- `gateway/executor.py` devient client RPC ; le broker seul exécute `gws`.
- Policy + lock restent appliqués (côté gateway et/ou broker).
- Auto-start depuis MCP si le broker n’écoute pas (DX simple).
- Credentials restent dans `~/.config/gws-accounts/` (limite assumée — 0003 plus tard).

## Critères d'acceptation

- [x] MCP fonctionne sans appeler `gws` directement depuis `executor.py`
- [x] Broker refuse profil verrouillé / policy (même sémantique Phase 1)
- [x] `./scripts/test.sh` vert + smoke broker
- [x] Docs architecture / threat-model mises à jour (Phase 2 A déployée)

## Notes

- Décision 2026-07-21 : **A + gws interne**, pas HTTP Google direct, pas vault.
- `ready:` posé le 2026-07-21 (soupape PO — démarrage immédiat Phase 2 A).
