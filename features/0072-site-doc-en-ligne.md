---
id: 0072
title: Site de doc en ligne (MkDocs Material + landing) déployé sur Vercel
type: feature
priority: P2
version:
epic: 0017
status: todo
ready: 2026-08-01
pr:
created: 2026-08-01
---

## Contexte / Problème

Il n'y a pas de vraie **doc produit en ligne**. Aujourd'hui :

- `site/docs.html` ne fait que **lister des liens vers des `.md` GitHub bruts** —
  pas une doc navigable (ni recherche, ni nav latérale, ni versions).
- Le `site/` (landing + hub) n'est **déployé nulle part** (aucun workflow Pages).
- La doc de référence ([docs/*.md](../docs/)) est riche mais dense, orientée
  contributeur (liens ADR, numéros de fiches, threat-model).

Un nouvel utilisateur n'a pas de porte « getting started » jolie et structurée,
aux standards d'un produit connu (Docker, Stripe…).

À distinguer de : [[0069]] (docs **in-app**, panneau admin), [[0070]] (README),
[[0019]] (copie EN des surfaces publiques).

## Décision (2026-08-01)

- **MkDocs Material** pour la doc (réutilise `docs/*.md`, recherche + nav + dark
  mode + versions, rendu moderne, mono-toolchain Python cohérent avec le projet).
- **Garder la landing** `site/index.html` (hero SVG, toggle FR/EN) comme accueil.
- Hébergement : **Vercel**, sous **`docs.elzinko.fr`** (infra existante de l'auteur).

## Proposition

- `mkdocs.yml` : thème Material, nav explicite (Getting started → Install →
  Connect account → Update → Security → Reference), recherche, dark mode.
- Réutiliser `docs/*.md` (adapter le strict nécessaire, sortir le jargon
  contributeur vers une section « Contributing »/référence).
- Assembler **landing (`/`) + docs (`/…`)** en une sortie statique.
- Déploiement Vercel (build reproductible) + domaine `docs.elzinko.fr`.
- EN-first (cohérent avec le rebrand) ; i18n FR/EN en phase 2 si besoin.

## Critères d'acceptation

- [ ] Site accessible en ligne sur `docs.elzinko.fr`.
- [ ] Recherche, navigation latérale et dark mode fonctionnels.
- [ ] Les pages viennent de `docs/*.md` (pas de simples liens vers GitHub).
- [ ] La landing existante est conservée comme accueil.
- [ ] Build reproductible (une commande) + déploiement documenté.

## Notes

- Épic [[0017]]. Le README ([[0070]]) pointera vers ce site (indirection : TLDR
  au repo, détail en ligne).
- Alternatives écartées : Docusaurus/Starlight (toolchain Node en plus), Mintlify
  (SaaS hébergé, contre l'éthos 100 % local), enrichir le `site/` fait main (tout
  réécrire à la main).
