---
id: 0077
title: Accès mobile souverain — approbation passkey + holder natif
type: epic
priority: P2
version:
epic:
status: todo
ready:
pr:
created: 2026-08-15
---

## Contexte / Problème

Aujourd'hui l'accès aux comptes Google est **local à un Mac** : serveur MCP stdio,
vault + broker loopback, approbation par Touch ID / admin web `127.0.0.1:4877`
(autorité *ambiante* — être devant le Mac déverrouillé vaut autorisation).

Le besoin (session 2026-08-15) : **utiliser ces comptes depuis un mobile**, dans des
contextes où l'agent tourne ailleurs que sur le Mac (Remote Control, Code on the web,
cowork, Dispatch), **Mac allumé OU éteint**, **sans serveur allumé en permanence**,
avec une **sécurité au repos maximale**, et le projet repensé **open source**.

Décision d'architecture : **[ADR-0008](../docs/adr/ADR-0008-acces-mobile-passkey-holder-natif.md)**
(accepté le 2026-08-15). Comparateur visuel : `docs/architecture/acces-mobile-comparateur.html`.

## Proposition

Épic parapluie qui **regroupe** les incréments menant à l'accès mobile souverain.
Modèle acté : 3 rôles découplés — *requester* (agent, jamais de confiance) /
*approver* (le téléphone, passkey WYSIWYS) / *holder* (jetons + exécution, scellés en
coffre matériel). Aucun travail propre : il coordonne ses enfants. **Jamais tirable.**

Incréments prévus (créés au fil de l'eau) :
- **0078 — Phase 1** : approbation par passkey sur l'archi *actuelle* (Mac holder allumé,
  téléphone approbateur). Faible risque, bénéfice immédiat, sans refonte.
- *(à créer)* Prototype holder natif Tauri 2 (sceller un jeton en coffre matériel + un
  appel Google, sur un OS mobile).
- *(à créer)* ADR enfant + fiche « relais aveugle » (joindre le holder derrière un NAT).
- *(à créer)* ADR enfant + fiche « enrôlement OAuth par appareil ».
- *(à créer)* Passage open source : licence Apache-2.0, modèle de menace public, CI multi-OS.

## Critères d'acceptation

- [ ] Depuis un téléphone, autoriser / verrouiller l'accès à plusieurs comptes Google,
      **Mac allumé ou éteint**, sans confier les jetons à un tiers.
- [ ] Toute action sensible exige une **approbation signée** (passkey, WYSIWYS) ; le
      contenu se limite à *ce que l'humain a vu et signé* (compte, cible, durée).
- [ ] Enfants livrés au moins jusqu'à la phase 1 (0078).

## Notes

- Décisions PO complémentaires (ADR-0008 §8) : enrôlement **par appareil** ; **garder le
  Python-macOS** existant + holder natif à côté (pas de big-bang) ; licence **Apache-2.0** ;
  démarrer par la **phase 1**.
- Priorité **proposée P2** — à confirmer par le PO (l'accès actuel fonctionne ; l'accès
  mobile est stratégique mais non bloquant).
- Recoupe partiellement [[0018]] (cross-platform hors macOS) et [[0045]] (droits par
  session) — à articuler, pas à dupliquer.
