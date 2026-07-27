---
id: 0033
title: Grant Drive « one-shot » demandé depuis la conversation, confirmé par Touch ID
type: feature
priority: P3
version:
epic: 0001
status: idea
ready:
pr:
created: 2026-07-27
---

## Contexte / Problème

Aujourd'hui, pour donner une zone d'écriture au LLM, l'humain quitte la
conversation, ouvre un terminal, et tape `gwsa grant perso "ZZ-TESTS" 2`
(Touch ID à la clé). Le tool `access_request` ne fait que **produire cette
commande** — il n'exécute rien (ADR-0001). C'est sûr, mais ça casse le fil :
le LLM demande, tu vas ailleurs, tu reviens.

La question posée (2026-07-27) : peut-on rester dans la conversation ? Le LLM
demanderait la zone, **tu** recevrais un Touch ID, et si tu poses le doigt, le
grant est créé — sans terminal.

## Idée (à cadrer, PAS encore décidée)

Un aller-retour où le **consentement humain** reste le seul déclencheur de la
mutation, mais au fil de la conversation :

1. Le LLM appelle `access_request kind=grant` (comme aujourd'hui).
2. Au lieu de te renvoyer une commande à taper, la gateway déclenche une
   invite Touch ID qui **nomme précisément** : le produit (google-mcp-multi-
   account), le compte (email), le dossier, la durée.
3. Doigt posé → un grant normal, borné dans le temps, est écrit. Doigt refusé
   → rien. Le LLM n'a jamais rien exécuté : il a demandé, la couche de
   confiance a tranché.

Ce n'est PAS « autoriser l'écriture ailleurs sans limite ». C'est le même
modèle par zones, avec le grant sollicité depuis le chat au lieu du terminal.

## Verrous à lever d'abord (pourquoi ce n'est pas trivial)

- **Provenance du dialogue.** Tant que la boîte système dit « swift » et non le
  produit (fiche 0032), un consentement au fil de l'eau ne vaut pas mieux
  qu'un clic réflexe. La fiche 0001 (élicitation signée) est le préalable :
  c'est elle qui fait monter `strongauth` de la simple présence (« un doigt »)
  à une **signature** liée à la demande exacte.
- **Frontière ADR-0001.** Le principe « le LLM ne déclenche jamais une mutation
  qui élargit son accès » doit rester vrai. Ici il tient *si* le déclencheur
  effectif est le doigt humain et non l'appel du LLM — à formaliser, car c'est
  une nuance fine et facile à éroder.
- **Accoutumance.** Un Touch ID par demande peut devenir un réflexe. Garder la
  granularité « une zone, une durée » plutôt que « un geste ».

## Critères d'acceptation

- [ ] À groomer — dépend de la fiche 0001 (provenance / signature).

## Notes

- Rattachée à l'épic/fiche 0001. Ne rien démarrer avant que 0032 (le dialogue
  nomme le produit et le compte) soit tranché.
- Alternative déjà en place et suffisante pour beaucoup de cas : `access_request`
  → l'humain tape `gwsa grant`. Cette fiche est un confort, pas un manque
  bloquant.
