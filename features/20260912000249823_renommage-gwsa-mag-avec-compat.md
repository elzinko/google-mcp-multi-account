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
  `ROOT`, `CLIENT`, `BROKER_HOST/PORT`) + tests bi-nom. ✅ *(commit 519d403)*
- **Lot 2** — reste des lectures `gateway/` (sessions, elicitation, api) + scripts Python
  (`policy-check`, `log-usage`, `elicitation-cli`). ✅ *(commit ec5b154)*
- **Lot 3** — compat bash (`bin/mag`, `scripts/*.sh`, `install.sh`) : normalisation en tête,
  pour tout ce qu'un humain ou un client MCP peut poser. ✅ *(commit e76b996)*
- **Lot 4** — émission `MAG_` : installeurs Claude Desktop/Code + `mag wire` écrivent `MAG_`
  dans les configs clients ; une entrée legacy `GWSA_` est **migrée** au prochain passage
  (backup). Doc « carte des noms » dans `configurer-client.md`. ✅
- **Lot 5** (plus tard) — retrait du repli `GWSA_`.

### Reporté volontairement (à faire dans une passe dédiée, non bloquant)

Le repli `GWSA_` étant en place partout, ces bascules sont sûres à faire plus tard :

- **Écritures internes gateway → sous-process** (Python) : `env["GWSA_SESSION_CAPS"]`,
  `GWSA_LOG_*`, `GWSA_GWS_CONFIG_DIR`, `GWSA_GIT_ROOT`, `GWSA_SESSION_ID`,
  `GWSA_USE_SESSION_GRANTS`, `GWSA_SESSION_DRIVE_ZONES`, `GWSA_ELICITATION_DIR`,
  `GWSA_ROOT` (posées par `broker_server.py`, `usage.py`, `elicitation.py`). Invisibles
  côté configs ; leurs lecteurs acceptent déjà les deux noms.
  ⚠️ `SESSION_CAPS` se teste par présence (voir garde de sécurité) : basculer l'écrivain
  **et** le lecteur ensemble. Le **signeur swift** lit `GWSA_ELICITATION_DIR`/`GWSA_ROOT`
  (binaire compilé, pas de helper) → auditer avant de renommer côté émission.
- **Émissions internes `bin/mag` → sous-process Python** : `GWSA_SYS_SWIFT`,
  `GWSA_SIGN_BIN`, `GWSA_ELICITATION_MOCK` (forward), `GWSA_LOG_*`, `GWSA_ROOT` pour
  l'élicitation. Éphémères, lecteurs Python bi-nom ; laissées pour ne pas toucher le
  chemin Touch ID en autonomie.
- **Snippets config `mag dev use` + `sandbox.sh` wire** : flux dev/sandbox (pas la config
  stable de prod). Même soin détection/préservation que les installeurs quand on le fera.
- **Boutons release/CI/test** : `GWSA_REPO`, `GWSA_TAGS_URL`, `GWSA_TARBALL_BASE`,
  `GWSA_MAIN_BRANCH`, `GWSA_RELEASE_TEST_CMD` — personne ne les pose en `MAG_` ;
  migrer avec le lot 5.
- **Constantes de tests de course** : `GWSA_*_TEST_RACE_DELAY_MS` (posées par `test.sh`).

## Critères d'acceptation

- [x] Une config passant `MAG_CLIENT` / `MAG_BROKER_PORT` / `MAG_ROOT` fonctionne. Testé.
- [x] Une config passant les anciens `GWSA_*` fonctionne **toujours** (repli). Testé (non-régression).
- [x] Le dossier `gws-accounts` (tokens) est **inchangé**.
- [x] `MAG_` a priorité sur `GWSA_` quand les deux sont présents. Testé.
- [x] `./scripts/test.sh` au vert (527 réussis).

## Comment vérifier

Lancer le serveur avec `MAG_BROKER_PORT=…` (sans `GWSA_BROKER_PORT`) → il l'utilise. Repasser à
`GWSA_BROKER_PORT` seul → il marche encore. Les deux ensemble → `MAG_` gagne.

## Notes

- Exécute l'**option 4** de la fiche nommage [`20260911211558435`](20260911211558435_coherence-nommage-mag-serveur-repo.md).
- Décision préservée : **ne pas renommer le serveur MCP** `google-multi-account` (breaking) ni le
  dossier `gws-accounts`. Ici, uniquement les **variables d'env**.
- Se fait sur la branche `feat/…` du POC (compat ⇒ le POC et `gma-feat` continuent de marcher).
