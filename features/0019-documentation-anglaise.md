---
id: 0019
title: English public surfaces — landing, docs & product copy
type: feature
priority: P1
version:
epic: 0017
status: todo
ready:
pr:
created: 2026-07-24
updated: 2026-07-29
---

## Contexte / Problème

Le projet vise une **audience internationale** (utilisateurs MCP hors FR) et une
**publication publique** du connecteur. Or les surfaces visibles de l’extérieur
sont encore majoritairement en **français** :

- le site public `site/` (landing `index.html`, `docs.html`, copy marketing) a
  été rédigé en FR par erreur — inadapté pour publier un MCP sur un registry /
  GitHub destinés à une audience EN ;
- README + docs d’accueil (`docs/mcp-setup.md`, `docs/setup-oauth.md`,
  `docs/usage.md`, …) restent FR ;
- messages CLI / erreurs de `mag` : langue non tranchée.

Sans anglais sur ces surfaces, la barrière d’entrée bloque l’adoption open-source
et la crédibilité d’une publication MCP. Voir épic [[0017]].

## Proposition

**Décision produit (defaults 2026-07-29, capture backlog)** :

- **Audience** : international MCP users (EN by default).
- **Priorité** : P1 — à traiter **avant** publication publique du MCP
  (registry / listing).
- **Langue** : English as source of truth for public surfaces ; FR optionnel
  en regard (`README.fr.md` / `site` i18n) si le coût reste raisonnable —
  sinon EN only pour le MVP publish.

Périmètre proposé (par couche) :

1. **`site/`** — landing + docs HTML + copy : passer en **English** (ou i18n
   FR/EN avec EN par défaut). Inclut meta/OG, CTA, titres de sections.
2. **README / docs publiques** orientées publication — README EN à la racine
   (source de vérité), docs de setup clés en EN.
3. **Cohérence brand name** *(optionnel, note)* — aligner le nom produit
   affiché (landing, README, connecteur) avec le slug repo /
   `google-multi-account` : trancher le wording public sans **renommer le
   repo** dans cette fiche.
4. **CLI / messages** — décider FR vs EN vs bilingue ; trancher EN si on vise
   l’adoption externe (peut être un sous-lot après le site).

Approche technique libre au sprint : rewrite EN one-shot **ou** petite couche
i18n (attributs `lang`, fichiers `en`/`fr`) — l’essentiel est **EN visible par
défaut** sur le chemin public.

## Critères d'acceptation

> **Réconciliation (2026-08-08).** L'essentiel est livré par le rebrand
> [#58](https://github.com/elzinko/google-mcp-multi-account/pull/58) : landing EN
> + bascule FR/EN, README EN, cohérence du nom produit. **Retournement** sur les
> docs : le site de doc [[0072]] ([#79](https://github.com/elzinko/google-mcp-multi-account/pull/79))
> a été fait **délibérément en français** → le critère « docs d'accueil EN » est
> **abandonné**. Seul reste réel : trancher la **langue des messages CLI**.

- [x] `site/index.html` et `site/docs.html` s’affichent en **anglais** par défaut
      — livré #58 (landing EN + bascule FR/EN persistée).
- [x] README anglais à la racine, à jour, cohérent avec le parcours publish /
      setup MCP — livré #58.
- [x] ~~Docs d’accueil clés en anglais~~ — **abandonné** : le site de doc
      ([[0072]] / #79) est délibérément **FR** (docs.elzinko.fr).
- [ ] Politique de langue des messages CLI décidée et documentée ← **seul reste**.
- [x] Nom produit affiché sur les surfaces publiques cohérent — livré #58
      (+ note nommage dépôt vs connecteur, commit dc5a341).

## Hors scope

- Renommage du repo GitHub / migration d’URLs.
- Traduction des ADR, diagrammes denses, et de toute la doc interne
  (coût > valeur au départ).
- Traduction de l’admin locale (`admin/`) sauf si un écran devient public.
- Publication effective sur un registry MCP (autre jalon) — cette fiche
  **débloque** le copy EN requis pour publier.

## Notes

- **Anti-doublon (2026-07-29)** : pas de nouvelle fiche 0043 — enrichissement
  de [[0019]] (même intention : EN pour audience non francophone). Élargi au
  `site/` + contexte « avant publish MCP ».
- Defaults capturés sans Q/R interactive : audience internationale MCP ;
  priorité P1 avant publish ; status `todo` (cadrée) mais **`ready:` vide** —
  passer le gate `ready 0019` avant tirage sprint.
- Ne pas traduire mécaniquement les 4 diagrammes ni les ADR au départ :
  prioriser chemin onboarding + landing publique.
- Enfant de l’épic [[0017]] (généraliser à d’autres utilisateurs).
