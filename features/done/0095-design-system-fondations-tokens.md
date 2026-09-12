---
id: 0095
title: Design system — fondations (tokens d'échelles + carte unifiée)
type: feature
priority: P0
product: google-mcp-multi-account
version:
epic: 0060
status: shipped
ready:
pr: "#128"
created: 2026-08-30
---

> **Livrée — superseded par #128 (2026-09-03).** La refonte « Cockpit » (épic
> [`0105`](0105-refonte-admin-cockpit.md), PR #128) a posé le système de tokens
> (`--sp`/`--fs`/`--r`/`--fw`/`--elev`) et la carte unifiée (`.ck-card`) que cette fiche
> proposait. Le socle est en place dans `admin/index.html` ; la fiche est marquée livrée à ce
> titre, sans PR propre.

## En clair

On pose les fondations invisibles du design system : cinq échelles chiffrées (espacement,
typo, arrondis, poids, élévation) en variables CSS, et une **carte unique** à la place des
trois recettes actuelles. Objectif : **aucun changement visuel volontaire**, juste
remplacer des dizaines de valeurs en dur par des tokens nommés.

Référence : [`docs/design/design-system-admin.md`](../../docs/design/design-system-admin.md) §1 et §3, ADR-0010.

## Contexte / problème

`admin/index.html` pose tailles, espacements et arrondis à la main : 13 tailles de police,
~10 arrondis, paddings ad hoc. Trois familles de cartes (`.card`/`.prow` en fond `--card`,
`.sess-card`/`.devcard` en fond `--bg`). Résultat : pas de « bouton unique » pour resserrer
le rythme visuel. Seules les couleurs sont déjà tokenisées.

## Proposition

- Ajouter dans `:root` (au-dessus des composants) : `--sp-1..-10`, `--fs-caption..-h1`,
  `--r-xs..-pill`, `--fw-normal/-medium/-semibold`, `--elev-0/-1/-2`. Neutres au thème.
- Migrer les valeurs les plus fréquentes vers ces tokens.
- Consolider la typo : 13 tailles → 6 tokens ; abandonner le poids 700 (identités en 600).
- Carte unifiée : un token carte (fond `--card`, `--r-lg`, `--sp-4`) + variante
  `.card--nested` ; migrer `.prow`, `.sess-card`, `.devcard` dessus.

## Critères d'acceptation

- [ ] Les cinq échelles sont définies dans `:root` et documentées.
- [ ] Le bloc `@media (prefers-color-scheme: dark)` ne redéfinit **que** des couleurs.
- [ ] `.sess-card`/`.devcard` passent en fond `--card` (fin de l'incohérence de fond).
- [ ] Diff visuel clair ET sombre quasi nul (pas de refonte, juste mise en système).
- [ ] Aucune régression `prefers-reduced-motion`.

## Comment vérifier

Lancer l'admin (`mag admin`), comparer avant/après en clair et sombre sur les écrans liste,
détail, sessions : le rendu doit être ~identique. `grep` de contrôle : plus de `font-size`
en dur hors tokens sur les composants migrés.
