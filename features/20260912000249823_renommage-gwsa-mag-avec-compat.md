---
id: "20260912000249823"
title: Renommage GWSA_ → MAG_ (variables d'env) avec compatibilité, sans rien casser
type: refactor
priority: P2
product: google-multi-account
version:
epic:
status: in-progress
ready: 2026-09-12
pr: "#142"
created: 2026-09-12
---

## En clair

Les variables d'environnement commencent par **`GWSA_`** — un vestige de l'ancien nom (`gwsa`).
Le produit s'appelle **`mag`** aujourd'hui. On renomme `GWSA_*` → `MAG_*`, **sans rien casser** :
le code lit **`MAG_` d'abord, `GWSA_` en repli** (compatibilité), et on migre progressivement.

**Ce qu'on ne touche PAS** : le dossier `~/.config/gws-accounts` (les **tokens**), le vault, la
Secure Enclave. Renommer le dossier serait un risque de perte d'accès — hors périmètre.

## Contexte / problème

~640 occurrences, **58 variables** (audit 2026-09-11). Réparties : `scripts/test.sh` (174, tests
hermétiques), `bin/mag` (53, passage d'env), le **code Python** (~24 lectures, déjà centralisées).
Variables sensibles :
- **dans les configs clients** : `GWSA_CLIENT`, `GWSA_BROKER_PORT` (Claude Desktop/Code les
  passent) → renommer sans compat **casse toutes les configs existantes**.
- **`GWSA_ROOT`** (273 occ) → racine de config + tokens → renommage bâclé = casse silencieuse.

D'où : **compat obligatoire**, jamais un find-replace sec.

## Stratégie (compatibilité d'abord, migration progressive)

1. **Lecture bi-nom (le cœur).** Un helper `env("X", default)` lit `MAG_X` sinon `GWSA_X` sinon
   `default`. Toutes les lectures Python passent par lui. En bash (`bin/mag`, scripts), une
   normalisation en tête : `X="${MAG_X:-${GWSA_X:-…}}"`. → **les deux noms marchent partout**.
2. **Émission en `MAG_`.** `bin/mag`, les scripts d'install (`install-claude-*.sh`) et le passage
   d'env aux sous-process **émettent `MAG_`**. Les anciennes configs (`GWSA_`) continuent via (1).
3. **Migration progressive.** Tests et docs passent à `MAG_` au fil de l'eau (pas bloquant : la
   compat les fait marcher tels quels entre-temps).
4. **Retrait de `GWSA_`** (repli) : **plus tard**, une fois tout migré et une fenêtre écoulée.

## Découpage en lots

- **Lot 1** — helper `env()` + compat des lectures **`gateway/`** (surtout les vars clients :
  `ROOT`, `CLIENT`, `BROKER_HOST/PORT`) + tests bi-nom. *(en cours)*
- **Lot 2** — reste des lectures `gateway/` (sessions, elicitation, api) + scripts Python
  (`policy-check`, `log-usage`, `elicitation-cli`).
- **Lot 3** — compat bash (`bin/mag`, `scripts/*.sh`) : normalisation en tête.
- **Lot 4** — émission `MAG_` (CLI + install clients) + doc (carte des noms).
- **Lot 5** (plus tard) — retrait du repli `GWSA_`.

## Critères d'acceptation

- [ ] Une config passant `MAG_CLIENT` / `MAG_BROKER_PORT` / `MAG_ROOT` fonctionne. Testé.
- [ ] Une config passant les anciens `GWSA_*` fonctionne **toujours** (repli). Testé (non-régression).
- [ ] Le dossier `gws-accounts` (tokens) est **inchangé**.
- [ ] `MAG_` a priorité sur `GWSA_` quand les deux sont présents. Testé.
- [ ] `./scripts/test.sh` au vert.

## Comment vérifier

Lancer le serveur avec `MAG_BROKER_PORT=…` (sans `GWSA_BROKER_PORT`) → il l'utilise. Repasser à
`GWSA_BROKER_PORT` seul → il marche encore. Les deux ensemble → `MAG_` gagne.

## Notes

- Exécute l'**option 4** de la fiche nommage [`20260911211558435`](20260911211558435_coherence-nommage-mag-serveur-repo.md).
- Décision préservée : **ne pas renommer le serveur MCP** `google-multi-account` (breaking) ni le
  dossier `gws-accounts`. Ici, uniquement les **variables d'env**.
- Se fait sur la branche `feat/…` du POC (compat ⇒ le POC et `gma-feat` continuent de marcher).
