---
id: 0081
title: Durcir la couche d'approbation passkey distante (suite revue Codex #113)
type: feature
priority: P2
version:
epic: 0077
status: todo
ready:
pr:
created: 2026-08-17
---

## Contexte / Problème

Le POC d'approbation par passkey distante ([0078](done/0078-approbation-passkey-archi-actuelle.md),
PR #113, [ADR-0009](../docs/adr/ADR-0009-approbation-passkey-distante.md)) livre « le téléphone
signe, le Mac vérifie et exécute — sinon rien ». Il reste **un durcissement non bloquant** (finding
P2 de la revue Codex, répondu en fil) : une course **TOCTOU inter-process** sur le compteur
anti-clonage `sign_count`.

Sont **déjà en place** dans #113 (donc hors de cette fiche) : le fail-closed, l'anti-rejeu
(`consume_nonce`), la liaison `session_id`, **et** le contrôle positif du chemin succès — le câblage
`gate → exécution` (`bin/gwsa` exécute `session_unlock` avec le payload **signé**) et son test E2E
hors-process (`scripts/test.sh` : une approbation valide fait bien passer `is_session_unlocked` à
vrai). *(Corrige une lecture initiale erronée qui croyait ce contrôle positif encore à câbler — relevé
par la revue Codex de #115, vérifié dans l'arbre.)*

Le **vrai canal out-of-process** (push / relais aveugle chiffré E2E, app mobile, holder natif) **ne
relève pas non plus de cette fiche** : c'est un incrément de l'épic
[0077](0077-acces-mobile-souverain.md) (« relais aveugle », déjà prévu), pas un durcissement de
l'existant.

## Proposition

**Sérialiser la vérification anti-clonage `sign_count` contre une course TOCTOU inter-process.**
Aujourd'hui l'appelant (`run_remote_approval_gate`, `gateway/remote_approval.py`) **charge
l'enrôlement AVANT** `verify_assertion`, qui lit-et-compare `sign_count <= enrollment.sign_count`
(l. 334) puis, plus loin, persiste `enrollment.sign_count = sign_count` + `_save_enrollment`
(l. 344-345). Un verrou **intra-fonction ne suffit pas** : deux process de vérification (deux
`gwsa … --remote` concurrents) chargent chacun le **même `sign_count` périmé** et peuvent tous deux
écraser `phone.json` — une passkey **clonée** rejouée passerait l'anti-clonage.

Il faut un **verrou inter-process** (verrou fichier, même classe que le TOCTOU `consume_nonce` /
broker) qui englobe un **rechargement frais** de l'enrôlement depuis le disque + comparaison +
persistance — pas l'objet enrôlement chargé *avant* le verrou. Le `sign_count` reste **authentifié
par la signature** (non forgeable) — d'où la sévérité **P2**.

## Critères d'acceptation

- [ ] **Modélisation de la course** : deux `gwsa … --remote` en **process séparés**, **chacun avec son
      propre défi frais**, signés depuis des **états d'authentificateur clonés portant le même prochain
      `sign_count`** (simule une passkey clonée) — vérifiés **concurremment**.
- [ ] **Invariant** : dans ce scénario, **exactement une** vérification réussit ; l'autre est refusée
      (son **rechargement frais sous verrou** voit le compteur déjà avancé). Le verrou est
      **inter-process** (fichier), couvrant reload + check + persistance — **pas** un verrou threads /
      objet partagé, qui masquerait la fuite inter-process.
- [ ] `./scripts/test.sh` vert.

## Notes

- Suite des revues Codex des PR #113 **et** #115 (findings P2, répondus en fil). Parent :
  [0078](done/0078-approbation-passkey-archi-actuelle.md) /
  [ADR-0009](../docs/adr/ADR-0009-approbation-passkey-distante.md) — dont les *Conséquences*
  soulignent déjà que `sign_count` doit être strictement croissant **et persisté à chaque
  vérification**, sinon une passkey clonée passerait (c'est le point durci ici).
- **Fiche sœur** de [0080](0080-durcir-capacites-fines-session.md) (« durcir … suite revue Codex #110 »
  sur la couche *session*) : même patron « durcissements différés d'une revue Codex ». Le TOCTOU est
  de la **même classe** que le TOCTOU `consume_nonce` déjà répertorié — à traiter d'un même geste de
  verrouillage inter-process si les deux sont tirés ensemble.
- **Écarté après vérification (revue Codex #115)** : un second item « renforcer le test CA3
  `NO_MUTATION` par un contrôle positif » — ce contrôle positif **existe déjà** (test E2E hors-process
  dans `scripts/test.sh` : approbation valide → `is_session_unlocked` vrai, câblage `bin/gwsa`), donc
  c'était un doublon.
- **Piège de test (relevé par Codex, passe 2 de #115)** : réutiliser **une seule** assertion sur deux
  process ne teste **pas** la course — `verify_assertion` exige `client_data == défi forgé`
  (`gateway/remote_approval.py:320-322`) et chaque `gwsa … --remote` forge son **propre** défi
  (`bin/gwsa`, `require_remote_approval`), donc le 2ᵉ process échoue sur la liaison au défi **avant** la
  comparaison du compteur. D'où le montage exigé : **deux défis distincts + deux signatures d'états
  clonés au même prochain `sign_count`**.
- Le vrai canal push / relais aveugle E2E + app mobile + holder natif **reste dans l'épic
  [0077](0077-acces-mobile-souverain.md)** (incrément « relais aveugle » déjà prévu) — hors de cette
  fiche.
