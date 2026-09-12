---
id: 0078
title: Approbation par passkey depuis le téléphone (archi actuelle, Mac holder)
type: feature
priority: P1
version:
epic: 0077
status: shipped
ready: 2026-08-16
pr: "#113"
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

**Le téléphone n'approuve que quand tu es loin du Mac.** Devant le Mac, on **garde le Touch ID du Mac** (l'existant) — le téléphone n'intervient pas. À distance (Remote Control, Dispatch), l'approbation bascule sur la **passkey du téléphone**.

Mécanisme (réutilise l'ADR-0005 : payload canonique décrivant l'action, `nonce` anti-rejeu, reçu vérifiable) :
1. Le Mac (holder) forge un **défi** lié à l'action **et à la session** (`session_id`, cf. #108 / ADR-0007).
2. Le défi voyage jusqu'au téléphone par un **canal distant** — notif push / relais — **jamais un QR** (tu n'es pas devant l'écran). Le canal n'a **pas besoin d'être secret** : la sécurité vient de WYSIWYS + vérification de signature côté Mac.
3. Le téléphone **affiche l'action** (WYSIWYS) et la **signe** (biométrie).
4. Le Mac **vérifie la signature** (device-bound) et exécute — sinon rien (fail-closed).

Périmètre **phase 1** (délibérément étroit) :
- Mac **allumé**, il reste le holder ; le téléphone n'exécute rien, ne détient aucun jeton.
- **Enrôlement** (geste unique, **à côté du Mac**) : par QR / scan local, on enregistre la clé publique d'une passkey **device-bound** du téléphone (platform authenticator, *non synchronisée* + vérification biométrique — cf. ADR-0008). C'est le **seul** usage du QR.
- **Approbation à distance** via un **canal minimal** (push / relais léger) ; le relais aveugle chiffré E2E complet est un incrément ultérieur.

## Critères d'acceptation

- [ ] Depuis le téléphone, approuver un `unlock` / `grant` par Face ID ; le Mac vérifie
      la signature et n'exécute **que** si elle est valide et fraîche (nonce non rejoué).
- [ ] Le téléphone **affiche l'action exacte** (compte, cible, durée) avant de signer.
- [ ] Un refus, un nonce expiré ou une signature invalide → **aucune** exécution (fail-closed).
- [ ] Aucun jeton Google ne quitte le Mac ; le téléphone ne stocke aucun secret Google.
- [ ] **Devant le Mac**, le Touch ID du Mac reste le chemin d'approbation (téléphone non requis).
- [ ] L'enrôlement **exige une passkey device-bound** — une *synced passkey* ou un PIN est refusé.
- [ ] Le défi est **lié à une session** (`session_id`) : une autre session ne peut pas rejouer l'approbation.

## Notes

- Découle de [ADR-0008](../docs/adr/ADR-0008-acces-mobile-passkey-holder-natif.md), Suites § phase 1.
- Réutilise l'élicitation signée [[0001]] / ADR-0005 (payload + nonce + reçu) — ne pas réinventer.
- **Articulation #108** : cette approbation par passkey **est** le « consentement distant » de la
  **phase B** de l'axe *droits par session* (ADR-0007 / PR #108). Même socle (ADR-0005) — à concevoir
  **une seule fois** ; elle se branche sur la couche *session* (phase A desktop de #108).
- Le relais aveugle et le holder natif mobile sont des **incréments ultérieurs** de l'épic [[0077]].
- Priorité **P1** (confirmée par le PO, 2026-08-15).
