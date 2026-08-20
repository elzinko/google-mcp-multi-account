---
id: 0084
title: Durcir consume_nonce contre une course TOCTOU inter-process (anti-rejeu partagé)
type: bug
priority: P2
version:
epic:
status: in-progress
ready: 2026-08-20
pr:
created: 2026-08-17
---

## En clair

L'anti-rejeu de l'élicitation signée avait une **faille de course** : deux process concurrents
(le Touch ID local **et** l'approbation passkey distante brûlent leur nonce par le même chemin)
pouvaient consommer le **même** nonce en même temps — un rejeu d'approbation signée passait.
On sérialise désormais `consume_nonce` derrière un **verrou inter-process** (`fcntl.flock`), avec
**rechargement frais sous le verrou** : un seul consommateur gagne, l'autre voit « rejeu refusé ».

## Contexte / Problème

`consume_nonce` (`gateway/elicitation.py:202-211`) est la **colonne anti-rejeu partagée** de
l'élicitation signée (ADR-0005) : le **Touch ID local** *et* l'**approbation par passkey distante**
([0078](done/0078-approbation-passkey-archi-actuelle.md), ADR-0009) brûlent leur nonce **par le même
chemin** (ADR-0009 : « garder **une seule** colonne anti-rejeu `consume_nonce` partagée »).

Or ce chemin est une **course TOCTOU** : `_load_nonces()` → `if nonce in nonces` (check) →
`_save_nonces()` (save), **sans atomicité**. Deux process concurrents peuvent tous deux charger l'état
« nonce absent », franchir le check, puis sauver — **acceptant deux fois le même nonce** : un rejeu
d'approbation signée passerait.

Défaut **latent** (il faut deux vérifications concurrentes sur le même nonce dans la fenêtre) et le
payload reste **signé** (non forgeable) — d'où **P2**. Mais il touche du code **en production** (le
Touch ID est live), pas seulement le POC passkey.

Relevé par la revue Codex de la PR #115 : la fiche [0083](0083-durcir-approbation-passkey-distante.md)
le mentionnait comme « déjà répertorié » alors qu'**aucune** fiche ne le suivait — ce trou est
désormais **owné ici**.

## Proposition

Sérialiser `load → check → save` de `consume_nonce` derrière un **verrou inter-process** (verrou
fichier, **même mécanisme** que le TOCTOU `sign_count` de
[0083](0083-durcir-approbation-passkey-distante.md)), englobant un **rechargement frais** du registre
de nonces **sous le verrou** — pas l'état chargé avant. Comme la colonne anti-rejeu est **unique et
partagée**, un seul verrou couvre les deux chemins (Touch ID + passkey).

## Critères d'acceptation

- [x] Deux `consume_nonce` **concurrents en process séparés** sur le **même nonce** ⇒ **un seul**
      réussit, l'autre lève « rejeu refusé (nonce déjà consommé) » — testé **multi-process**.
- [x] Le verrou est **inter-process** (fichier), couvrant reload + check + save du registre — **pas**
      un verrou threads / objet partagé, qui masquerait la fuite inter-process.
- [x] `./scripts/test.sh` vert.

## Comment vérifier

- Suite : `./scripts/test.sh` — assertion **« consume_nonce : course multi-process — exactement un
  gagnant, l'autre voit le rejeu »** (section « fiche 0084 »), suite verte à **388/0**.
- Le test lance **2 vrais sous-process `python3`** sur le même nonce (barrière de départ + hook de
  fenêtre `GWSA_ELICITATION_TEST_RACE_DELAY_MS`) ⇒ exactement **1 `ok` + 1 rejeu**. Sans le verrou
  (retiré temporairement) : **2 `ok`** (RED prouvé).
- Non-régression : les tests `remote_approval`/passkey qui partagent `consume_nonce` restent verts.

## Notes

- **Fiche sœur** de [0083](0083-durcir-approbation-passkey-distante.md) (TOCTOU `sign_count`) : **même
  classe**, **même correctif** (verrou inter-process + rechargement frais). Les deux se traitent d'un
  seul geste de verrouillage si tirées ensemble.
- Colonne anti-rejeu partagée : [ADR-0005](../docs/adr/ADR-0005-elicitation-signee-v2.md) (élicitation
  signée) / [ADR-0009](../docs/adr/ADR-0009-approbation-passkey-distante.md) (§ « une seule colonne
  anti-rejeu »). Recoupe [0001](0001-elicitation-signee-strongauth-v2.md) (élicitation signée).
- Découle de la revue Codex de la PR #115 (finding P2 répondu en fil).

## Grooming (PO — 2026-08-20)

Tirée **avant** le head P1 0019 (docs anglaises) — skip **assumé et journalisé** (choix humain,
comme 0087). Cible **vérifiée** : `consume_nonce` / `_load_nonces` / `_save_nonces` présents
(`gateway/elicitation.py:176-211`) ; **aucun** verrou inter-process existant dans `gateway/` → à
introduire (greenfield). Fiche sœur 0083 encore active → pas de helper à réutiliser (on en produit
un réutilisable pour elle).

**Périmètre tranché (DoR) :**

- **Verrou** = `fcntl.flock` (LOCK_EX) sur un lockfile dédié dans `GWSA_ROOT` (à côté du store de
  nonces). Enveloppe **reload → check → save** de `consume_nonce`, avec **rechargement frais SOUS le
  verrou** (jamais l'état chargé avant). POSIX → macOS + CI Linux.
- **Helper réutilisable** : un petit `with _file_lock(path):` (context manager) — 0083 le réutilisera.
  Un **seul** verrou partagé couvre Touch ID + passkey (colonne anti-rejeu unique).
- **Test** = **multi-process** hermétique : deux sous-process `python3` appellent `consume_nonce` sur
  le **même** nonce en concurrence ⇒ **un seul** réussit, l'autre lève « rejeu refusé ». Vrai
  inter-process (pas des threads / un objet partagé).
- **Non-régression** = `./scripts/test.sh` vert.
- **Hors périmètre** : 0083 (sign_count) reste une fiche séparée (per-feature) — juste rendue triviale
  par le helper. Ne pas élargir `consume_nonce` au-delà de l'atomicité.

DoR : problème cité & vérifié · valeur (intégrité anti-rejeu signé) · critères testables multi-process
· mécanisme tranché · aucune dépendance externe → **prêt à tamponner**.
