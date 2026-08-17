---
id: 0082
title: Durcir consume_nonce contre une course TOCTOU inter-process (anti-rejeu partagé)
type: bug
priority: P2
version:
epic:
status: todo
ready:
pr:
created: 2026-08-17
---

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

Relevé par la revue Codex de la PR #115 : la fiche [0081](0081-durcir-approbation-passkey-distante.md)
le mentionnait comme « déjà répertorié » alors qu'**aucune** fiche ne le suivait — ce trou est
désormais **owné ici**.

## Proposition

Sérialiser `load → check → save` de `consume_nonce` derrière un **verrou inter-process** (verrou
fichier, **même mécanisme** que le TOCTOU `sign_count` de
[0081](0081-durcir-approbation-passkey-distante.md)), englobant un **rechargement frais** du registre
de nonces **sous le verrou** — pas l'état chargé avant. Comme la colonne anti-rejeu est **unique et
partagée**, un seul verrou couvre les deux chemins (Touch ID + passkey).

## Critères d'acceptation

- [ ] Deux `consume_nonce` **concurrents en process séparés** sur le **même nonce** ⇒ **un seul**
      réussit, l'autre lève « rejeu refusé (nonce déjà consommé) » — testé **multi-process**.
- [ ] Le verrou est **inter-process** (fichier), couvrant reload + check + save du registre — **pas**
      un verrou threads / objet partagé, qui masquerait la fuite inter-process.
- [ ] `./scripts/test.sh` vert.

## Notes

- **Fiche sœur** de [0081](0081-durcir-approbation-passkey-distante.md) (TOCTOU `sign_count`) : **même
  classe**, **même correctif** (verrou inter-process + rechargement frais). Les deux se traitent d'un
  seul geste de verrouillage si tirées ensemble.
- Colonne anti-rejeu partagée : [ADR-0005](../docs/adr/ADR-0005-elicitation-signee-v2.md) (élicitation
  signée) / [ADR-0009](../docs/adr/ADR-0009-approbation-passkey-distante.md) (§ « une seule colonne
  anti-rejeu »). Recoupe [0001](0001-elicitation-signee-strongauth-v2.md) (élicitation signée).
- Découle de la revue Codex de la PR #115 (finding P2 répondu en fil).
