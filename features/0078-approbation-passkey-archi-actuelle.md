---
id: 0078
title: Approbation par passkey depuis le téléphone (archi actuelle, Mac holder)
type: feature
priority: P1
version:
epic: 0077
status: todo
ready:
pr:
created: 2026-08-15
---

## Contexte / Problème

L'approbation d'une action sensible (unlock, grant, add) passe aujourd'hui par le
**Touch ID du Mac** (élicitation signée, ADR-0005) et/ou l'admin web locale — donc
uniquement **devant le Mac**. Impossible d'approuver depuis un téléphone quand on
pilote une session à distance (Remote Control, Dispatch).

Or le téléphone est un **authentificateur de premier ordre** (passkey / WebAuthn,
Face ID). Première marche vers l'ADR-0008, **sans refonte** : le Mac reste le holder
(vault + broker), seul l'**approbateur** se déporte sur le téléphone.

## Proposition

Brancher la **passkey du téléphone** comme signataire de l'élicitation existante, en
**réutilisant** le protocole de l'ADR-0005 (payload canonique décrivant l'action,
`nonce` anti-rejeu, reçu vérifiable). Le Mac forge le défi → le téléphone l'affiche
(**WYSIWYS**) et le signe (Face ID) → le Mac vérifie la signature et exécute.

Périmètre **phase 1** (délibérément étroit) :
- Mac **allumé**, il reste le holder ; le téléphone n'exécute rien, ne détient aucun jeton.
- Enrôlement d'**une** passkey de téléphone comme approbateur autorisé (clé publique connue du Mac).
- Acheminement du défi puis de la signature : d'abord le cas **LAN / même compte** ; le
  relais aveugle (NAT, agent cloud) est hors phase 1 (ADR/fiche enfant).

## Critères d'acceptation

- [ ] Depuis le téléphone, approuver un `unlock` / `grant` par Face ID ; le Mac vérifie
      la signature et n'exécute **que** si elle est valide et fraîche (nonce non rejoué).
- [ ] Le téléphone **affiche l'action exacte** (compte, cible, durée) avant de signer.
- [ ] Un refus, un nonce expiré ou une signature invalide → **aucune** exécution (fail-closed).
- [ ] Aucun jeton Google ne quitte le Mac ; le téléphone ne stocke aucun secret Google.

## Notes

- Découle de [ADR-0008](../docs/adr/ADR-0008-acces-mobile-passkey-holder-natif.md), Suites § phase 1.
- Réutilise l'élicitation signée [[0001]] / ADR-0005 (payload + nonce + reçu) — ne pas réinventer.
- Le relais aveugle et le holder natif mobile sont des **incréments ultérieurs** de l'épic [[0077]].
- Priorité **P1** (confirmée par le PO, 2026-08-15).
