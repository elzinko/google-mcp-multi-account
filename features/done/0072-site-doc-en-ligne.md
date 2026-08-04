---
id: 0072
title: Site de doc en ligne (MkDocs Material + landing) déployé sur Vercel
type: feature
priority: P2
version:
epic: 0017
status: shipped
ready: 2026-08-01
pr: "#79"
created: 2026-08-01
updated: 2026-08-01
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
- Hébergement : **Vercel**, sous **`google-multi-account-docs.vercel.app`** (infra existante de l'auteur).

## Proposition

- `mkdocs.yml` : thème Material, nav explicite (Getting started → Install →
  Connect account → Update → Security → Reference), recherche, dark mode.
- Réutiliser `docs/*.md` (adapter le strict nécessaire, sortir le jargon
  contributeur vers une section « Contributing »/référence).
- Assembler **landing (`/`) + docs (`/…`)** en une sortie statique.
- Déploiement Vercel (build reproductible) + domaine `google-multi-account-docs.vercel.app`.
- EN-first (cohérent avec le rebrand) ; i18n FR/EN en phase 2 si besoin.

## Critères d'acceptation

- [ ] Site accessible en ligne sur `google-multi-account-docs.vercel.app` (connexion Vercel + DNS — geste humain, voir ci-dessous).
- [x] Recherche, navigation latérale et dark/light fonctionnels (Material — build vérifié localement).
- [x] Les pages viennent de `docs/*.md` (pas de simples liens vers GitHub).
- [x] La landing existante (`site/`) est conservée (intacte, non touchée).
- [x] Build reproductible (`python3 -m pip install -r requirements-docs.txt && mkdocs build`).

## Livré (Phase 1) — branche `feat/0072-site-doc-en-ligne`

- `mkdocs.yml` (Material : nav curée, recherche FR, dark/light, cartes, icônes).
- `docs/index.md` : accueil produit (pitch + quickstart `curl` + liens).
- `requirements-docs.txt`, `vercel.json` (build + `outputDirectory: _site`), `.gitignore` (`_site/`).
- Build **vérifié** dans un venv (`rc=0`) + rendu contrôlé au navigateur (light).

### Reste à faire (gestes humains / suite)

- **Déploiement Vercel** (dashboard, non scriptable par le LLM) : importer le repo,
  laisser `vercel.json` piloter le build, puis ajouter le domaine `google-multi-account-docs.vercel.app`.
- **Liens vers les sources** (`../scripts/`, `../features/`, `../SECURITY.md`…) :
  19 warnings de build — liens hors `docs/`. À convertir en URLs GitHub (idéalement
  avec la passe EN [[0019]] pour ne pas éditer les docs deux fois).
- **Landing → docs** : repointer le lien « Docs » de `site/` vers `google-multi-account-docs.vercel.app`
  une fois le domaine en ligne.

## Notes

- Épic [[0017]]. Le README ([[0070]]) pointera vers ce site (indirection : TLDR
  au repo, détail en ligne).
- Alternatives écartées : Docusaurus/Starlight (toolchain Node en plus), Mintlify
  (SaaS hébergé, contre l'éthos 100 % local), enrichir le `site/` fait main (tout
  réécrire à la main).
