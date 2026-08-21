---
id: 0083
title: Durcir la couche d'approbation passkey distante (suite revue Codex #113)
type: feature
priority: P2
version:
epic: 0077
status: in-progress
ready: 2026-08-21
pr:
created: 2026-08-17
---

## En clair

On approuve une action sensible depuis son téléphone (passkey). Un **compteur** doit monter à chaque
usage, pour empêcher qu'une passkey **copiée** rejoue un vieil accord. Mais deux vérifications lancées
**au même instant** pouvaient lire le même vieux compteur et **accepter les deux** — une passkey copiée
serait passée une fois. On pose un **verrou** (le même qu'en 0084, extrait en module partagé) autour de
« lire le compteur → vérifier → écrire » : la 1ʳᵉ vérif monte le compteur, la 2ᵉ le voit monté et refuse.
Le verrou couvre aussi le **ré-enregistrement** d'un téléphone (pour éviter qu'il écrase une vérif).

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
Le **vrai chemin CLI** — `bin/gwsa … --remote` → `scripts/remote-approval-cli.py verify` →
**`close_remote_challenge`** (`gateway/remote_approval.py:166`) — **charge l'enrôlement AVANT**
`verify_assertion` (tout comme l'appelant in-process `run_remote_approval_gate`). `verify_assertion`
lit-et-compare `sign_count <= enrollment.sign_count` (l. 334) puis, plus loin, persiste
`enrollment.sign_count = sign_count` + `_save_enrollment` (l. 344-345). Un verrou **intra-fonction ne
suffit pas** : deux process de vérification (deux `gwsa … --remote` concurrents) chargent chacun le
**même `sign_count` périmé** et peuvent tous deux écraser `phone.json` — une passkey **clonée** rejouée
passerait l'anti-clonage.

Il faut un **verrou inter-process** (verrou fichier, même classe que le TOCTOU `consume_nonce` /
broker) qui englobe un **rechargement frais** de l'enrôlement depuis le disque + comparaison +
persistance — pas l'objet enrôlement chargé *avant* le verrou — **dans `close_remote_challenge` (le
point d'entrée CLI réel) comme dans tout autre point de vérification** (`run_remote_approval_gate`). Le
`sign_count` reste **authentifié par la signature** (non forgeable) — d'où la sévérité **P2**.

**Tout écrivain de `phone.json` doit prendre ce même verrou** — pas seulement les points de
vérification. `enroll_phone` (`gateway/remote_approval.py:195` → `_save_enrollment` l.222) réécrit
l'enrôlement : un `enroll_phone` concurrent d'une vérification peut remplacer `phone.json` **après** le
rechargement verrouillé du vérifieur mais **avant** sa persistance (l.345) — le vérifieur écraserait
alors le **nouvel** enrôlement avec l'**ancien** identifiant + compteur. La sérialisation porte donc sur
le **fichier** (tous les writers : vérification *et* enrôlement), pas sur un chemin d'entrée.

## Critères d'acceptation

- [x] **Modélisation de la course** : deux `gwsa … --remote` en **process séparés**, **chacun avec son
      propre défi frais**, signés depuis des **états d'authentificateur clonés portant le même prochain
      `sign_count`** (simule une passkey clonée) — vérifiés **concurremment**.
- [x] **Invariant** : dans ce scénario, **exactement une** vérification réussit ; l'autre est refusée
      (son **rechargement frais sous verrou** voit le compteur déjà avancé). Le verrou est
      **inter-process** (fichier), couvrant reload + check + persistance — **pas** un verrou threads /
      objet partagé, qui masquerait la fuite inter-process.
- [x] **Interleaving enrôlement ↔ vérification** : un `enroll_phone` qui remplace `phone.json`
      pendant la fenêtre verrouillée d'un vérifieur **ne peut ni être écrasé** par la persistance du
      vérifieur, **ni corrompre** le compteur — `enroll_phone` prend le **même** verrou fichier (reload
      + write sous verrou) que la vérification.
- [x] `./scripts/test.sh` vert.

## Comment vérifier

- Suite : `./scripts/test.sh` — section « remote_approval : verrou anti-clonage inter-process sur
  sign_count (fiche 0083) », **2 tests**, suite verte à **391/0**.
- **Course de clones** : 2 vérifs concurrentes (2 défis frais distincts + 2 signatures d'états clonés au
  **même** compteur) ⇒ **exactement 1 accepté, 1 refusé** (le refusé, son reload frais sous verrou voit
  le compteur avancé). Sans le verrou : les deux passent (RED prouvé).
- **Interleaving** : un ré-enregistrement (`enroll_phone`) pendant la fenêtre verrouillée d'une vérif
  n'est **ni écrasé ni corrompu** (même verrou).
- Non-régression : tests 0084 `consume_nonce` + `remote_approval`/passkey existants restent verts.

## Notes

- Suite des revues Codex des PR #113 **et** #115 (findings P2, répondus en fil). Parent :
  [0078](done/0078-approbation-passkey-archi-actuelle.md) /
  [ADR-0009](../docs/adr/ADR-0009-approbation-passkey-distante.md) — dont les *Conséquences*
  soulignent déjà que `sign_count` doit être strictement croissant **et persisté à chaque
  vérification**, sinon une passkey clonée passerait (c'est le point durci ici).
- **Fiche sœur** de [0080](0080-durcir-capacites-fines-session.md) (« durcir … suite revue Codex #110 »
  sur la couche *session*) : même patron « durcissements différés d'une revue Codex ». Le TOCTOU est
  de la **même classe** que le TOCTOU `consume_nonce` — désormais suivi par sa propre fiche
  [0084](0084-durcir-consume-nonce-toctou.md) (anti-rejeu partagé Touch ID + passkey) — à traiter d'un
  même geste de verrouillage inter-process si les deux sont tirés ensemble.
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

## Grooming (PO — 2026-08-20)

Fiche sœur de 0084 (livrée #125). Cibles **vérifiées** dans `gateway/remote_approval.py` :
`close_remote_challenge` (158), `run_remote_approval_gate` (349), `verify_assertion` (309 — check
l.334, persist l.344), `enroll_phone` (195), `enrollment_path()` (53 → `phone.json`). Le helper
`_file_lock` est **sur main** (livré en 0084, `gateway/elicitation.py:57`).

**Périmètre tranché (DoR) :**

- **Réutiliser le verrou via extraction** : sortir `_file_lock` de `elicitation.py` vers un module
  partagé (ex. `gateway/_filelock.py`, `file_lock` public) ; `elicitation.py` l'importe (`consume_nonce`
  **inchangé**) ; `remote_approval.py` l'importe. Plus propre qu'un import cross-module d'un helper `_`-privé.
- **Verrouiller TOUS les writers de `phone.json`** : `close_remote_challenge` **et**
  `run_remote_approval_gate` (les 2 chemins de vérif) rechargent l'enrôlement **frais SOUS le verrou**
  puis check + persist ; `enroll_phone` prend **le même** verrou (reload + write). Lockfile
  `enrollment_path().with_suffix('.lock')` (`phone.lock`).
- **Test (piège de liaison au défi)** : deux `gwsa … --remote` en **process séparés**, **chacun son
  défi frais**, signés depuis des **états clonés au même prochain `sign_count`** → concurrents ⇒
  **exactement un** réussit (l'autre refusé — `verify_assertion` renvoie `False`, son reload frais voit
  le compteur avancé). **Plus** un test **interleaving enroll ↔ vérif**. Vrai inter-process (pas threads).
- **Non-régression** : `./scripts/test.sh` vert + tests `remote_approval`/passkey existants.
- **Hors périmètre** (confirmé par la fiche) : vrai canal push / relais aveugle + app mobile = épic 0077.

DoR : problème cité & vérifié · mécanisme tranché (réutilise le verrou 0084) · critères testables
multi-process · pas de dépendance externe → **prêt à tamponner**.
