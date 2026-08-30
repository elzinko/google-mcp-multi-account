---
id: 0104
title: App shell responsive — navigation et rendu mobile pro (bottom-nav + top-bar)
type: feature
priority: P1
product: google-mcp-multi-account
version:
epic: 0060
status: todo
ready:
pr:
created: 2026-08-30
---

## En clair

En mobile, l'admin fait « pas pro » : le titre casse sur trois lignes, le badge de version
déborde hors de l'écran, et la barre du haut s'empile en vrac. La cause : **aucune règle
responsive** sur le header — il a été pensé pour une seule ligne en grand écran. On répare
la barre du haut, on sort le badge de version de l'identité, et on donne à la navigation un
**mode mobile propre** (barre d'onglets en bas, façon app). Tout en vanilla + tokens, zéro
dépendance.

Fait suite à 0103 (qui a restructuré le header desktop mais sans passe mobile). Constaté le
2026-08-30 à l'émulation 375px.

## Contexte / problème

Le `<header>` compte entièrement sur `flex-wrap:wrap` sans plan B. Sous ~640px :

- **Titre sur 3 lignes** : `h1` sans `nowrap`, `.brand` sans `min-width:0`.
- **Badge de version qui déborde** : `#verBadge` en `white-space:nowrap`, stylé en accent
  (la couleur la plus forte) — il fait « debug », pas « produit », et sort de l'écran.
- **Empilement absurde** : `.tools{margin-left:auto}` en mode wrap force les outils sur une
  ligne à part → titre / badge coupé / « — admin » orphelin / nav / outils.
- **Cibles tactiles** toutes sous 44px (nav, icônes, cadenas).
- **Emails de compte tronqués** ; CTA « Connecter un compte » qui flotte ; `.page-head` et
  `.filters` (Journal) qui wrappent en escalier.

## Proposition

**Navigation : top-bar responsive + bottom-nav sur mobile (< 640px).** Les 3 pages
(Comptes / Sessions / Journal) sont des destinations de même niveau → barre d'onglets. Une
seule structure HTML, deux rendus CSS ; `syncNav()` marque déjà `aria-current`, aucun JS à
changer. Hamburger écarté (cache la nav derrière un clic pour 3 destinations de pair).

- **Badge de version** : déplacé en fin de `.tools`, style muté (`--mut` + `--line`), masqué
  < 640px.
- **Titre** : nom complet masqué < 640px (repère court « admin » + glyphe) ; `h1` sur
  `--fs-h2`, `nowrap` + ellipsis ; `.brand{min-width:0}`.
- **Breakpoint** structurel à 640px (aligné sur `.sess-row`), ajustement fin < 400px.
- **Cibles tactiles** : plancher 44px sous 640px.
- **`.page-head`** empilé proprement ; **`.filters`** Journal replié dans un `<details>`.
- **`.prow`** reflow < 480px (email complet, chevron masqué) ; CTA pleine largeur.

### Découpage en lots (chacun testable à 375px)

1. **App-shell responsive (top-bar)** — le plus rentable : corrige à lui seul titre 3 lignes,
   débordement du badge, empilement. Un seul changement HTML (déplacer `#verBadge`).
2. **Bottom-nav mobile** — `.nav` en barre fixe en bas < 640px (aucun JS).
3. **`.page-head` + filtres** — empilement propre, filtres Journal repliés.
4. **Rangées de compte + CTA** — reflow email, CTA pleine largeur.

## Critères d'acceptation

- [ ] À 375px : titre sur une ligne (ou repère court), badge de version non débordant.
- [ ] Navigation utilisable au pouce (bottom-nav, cibles ≥ 44px), page active marquée.
- [ ] `.page-head` et filtres empilent proprement (pas d'escalier).
- [ ] Emails de compte non tronqués ; CTA pleine largeur.
- [ ] Rendu correct en clair et sombre, desktop et mobile ; zéro dépendance ajoutée.

## Comment vérifier

Émuler 375px dans le navigateur (ou un vrai téléphone via l'admin local) et parcourir
Comptes / Sessions / Journal : la barre du bas fonctionne, rien ne déborde, les cibles sont
prenables au doigt. Vérifier aussi le desktop (non régressé) et le thème sombre.
