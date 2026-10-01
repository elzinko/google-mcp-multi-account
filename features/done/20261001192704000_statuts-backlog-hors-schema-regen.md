---
id: "20261001192704000"
title: Aligner le vocabulaire de statut backlog sur le schéma du regen (todo/blocked rendus « ❓ » + churn de l'index)
type: bug
priority: P2
product: google-multi-account
version:
epic:
status: shipped
ready: 2026-10-01
pr: "7d5904e"
created: 2026-10-01
---

## En clair

Certaines fiches portent un statut que le générateur d'index **ne connaît plus**. À chaque
régénération de `features/BACKLOG.md`, ces fiches basculent en « ❓ » et polluent le diff — alors
que personne n'a touché à leur contenu. L'index est pourtant marqué « ne pas éditer à la main » :
on ne peut donc pas corriger à la main sans que le regen suivant recasse tout. Il faut **aligner
le vocabulaire des statuts** sur le schéma unique du générateur.

> Trouvée en shippant la fiche [[20261001121405000_gate-drive-corbeille-signee-delete]] (#157) :
> le regen voulait transformer `0101` « ⛔ blocked » en « ❓ blocked ». J'ai restauré la ligne à la
> main pour ne pas polluer le ship, mais le piège reste entier.

## Contexte / problème

Le générateur `regen-backlog.sh` (mega-city) définit **un seul** schéma de statuts, miroir de
`src/core/fiche-schema.ts` :

```
idea · ready · in-progress · shipped · superseded · merged · split
```

Tout statut hors de cette liste est rendu « ❓ <statut> » dans l'index. Or, sur `main`,
**3 fiches** et **le template** utilisent encore l'ancien vocabulaire (`todo`, `blocked`) :

| Fichier | Statut porté | Rendu au regen |
|---|---|---|
| [0089](0089-choix-profil-navigateur-oauth-add.md) | `todo` | ❓ todo |
| [0090](0090-documenter-statut-oauth-verification.md) | `todo` | ❓ todo |
| [0101](0101-nom-de-session-fourni-par-le-client.md) | `blocked` | ❓ blocked |
| `features/feature-template.md` | (doc) `idea \| todo \| in-progress \| blocked \| shipped` | — |

**Cause racine** : le template local `features/feature-template.md` enseigne encore
`todo`/`blocked`. Toute nouvelle fiche copiée dessus hérite d'un statut hors-schéma. Le symptôme
(❓ + churn) se reproduira tant que le template et le schéma divergent.

Conséquence : l'index est déjà dans un état mixte (certaines lignes « ❓ », d'autres à l'ancienne
icône selon la génération). Chaque regen rejoue la bascule → diffs parasites, et un ship doit
restaurer les lignes à la main (fait pour #157).

## Proposition

Deux directions — **à trancher au grooming** (la seconde touche un dépôt tiers) :

- **Option A (dans ce repo, recommandée)** : migrer les 3 fiches vers un statut du schéma
  (`0089`/`0090` → `idea` ou `ready` selon leur maturité réelle ; `0101` → `idea`, puisque
  « bloquée » = pas encore actionnable), **et** corriger le vocabulaire du template
  `features/feature-template.md` pour qu'il liste exactement le schéma. Pas de « blocked » dans le
  schéma → noter l'état « en attente » autrement (ex. une note dans le corps, pas le statut).
- **Option B** : réintroduire `todo`/`blocked` dans le schéma (mega-city : `regen-backlog.sh`
  **et** `src/core/fiche-schema.ts`, gardés par leur test de contrat). Plus lourd, cross-repo, et
  rouvre un vocabulaire que le schéma avait resserré — à ne faire que si ces états sont voulus.

## Critères d'acceptation

- [ ] Après regen, **aucune** ligne « ❓ » dans `features/BACKLOG.md`.
- [ ] Un **second** regen d'affilée est un **no-op** (diff vide) — preuve que l'index et les
      front-matters sont d'accord.
- [ ] Le template `features/feature-template.md` ne propose que des statuts du schéma.
- [ ] Un ship de fiche ne nécessite plus de restaurer de ligne à la main.

## Comment vérifier

```bash
# 1) aucun statut hors-schéma (le scan des front-matters doit être vide)
for f in features/[0-9]*.md features/done/[0-9]*.md; do
  s=$(sed -n 's/^status:[[:space:]]*//p' "$f" | sed 's/[[:space:]]*#.*//' | head -1)
  case "$s" in idea|ready|in-progress|shipped|superseded|merged|split) ;; *) echo "$f: $s";; esac
done
# 2) regen idempotent : deux passes produisent le MÊME index
cp features/BACKLOG.md /tmp/b1 && bash <regen-backlog.sh> "$PWD" >/dev/null && diff -q /tmp/b1 features/BACKLOG.md
```
