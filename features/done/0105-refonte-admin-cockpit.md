---
id: 0105
title: Refonte de l'admin — adopter le design system « Cockpit » (par écran)
type: epic
priority: P1
product: google-mcp-multi-account
version:
epic:
status: shipped
ready:
pr: "#128"
created: 2026-08-31
---

## En clair

On remplace la peau de l'admin par le design system **Cockpit** (console cobalt + chaleur
émeraude), validé en maquette. Le **câblage JS reste** (données, actions, pages
Sessions/Journal, filtres, tri, nav responsive) ; on change le **CSS et les classes du
HTML**, écran par écran.

Maquette de référence : la page « Système de design Cockpit » (artifact). Fondation CSS +
galerie + 6 écrans, relue par un panel (54 remarques, critiques corrigées).

## Contexte / décision

- La PR #127 (version incrémentale) a été **fermée** : son rendu ne satisfaisait pas. Son
  câblage est conservé comme socle (branche `feat/0105-refonte-cockpit` partie de
  `feat/0099`).
- Contrainte tenue : **vanilla + tokens, zéro dépendance, pas de build**.
- Migration **incrémentale sûre** : les classes Cockpit sont **préfixées `ck-`** pour
  cohabiter sans collision avec l'ancien CSS. On migre un écran, on retire l'ancien
  équivalent. À la fin, l'ancien CSS disparaît.

## Découpage en lots (fiches enfants à créer au fil de l'eau)

1. **Fondation + coquille + Comptes** — intégrer `foundation.css` (préfixé) dans l'admin ;
   refaire le shell (rail/nav + top-bar mobile + hamburger) et l'écran Comptes (liste +
   tuiles) en classes Cockpit, sur les vraies données. Écran pilote.
2. **Détail + Configurer les droits** — vue détail + la modale policy (préréglages
   segmentés, cases, zones) en Cockpit.
3. **Sessions** — page Sessions (cartes régulières, tri, liste/vignettes, cadenas, actions).
4. **Journal** — page Journal (filtres, table, journal par session).
5. **Setup + Connexion + états** — panneau setup/IAM, modale « Connecter un compte »,
   toasts, dialogs de confirmation.
6. **Nettoyage** — retirer l'ancien CSS, dépréfixer si utile, passe finale contraste/mobile.

## Critères d'acceptation (épic)

- [ ] Tous les écrans de l'admin adoptent le design system Cockpit (plus d'ancien look).
- [ ] Le câblage JS (pages, filtres, tri, actions) fonctionne comme avant.
- [ ] Clair ET sombre corrects ; responsive/mobile ; contraste AA.
- [ ] Zéro dépendance ajoutée ; `./scripts/test.sh` au vert (hors flake sandbox connu).
- [ ] Punch-list du panel (remarques moyennes/mineures) traitée ou tracée.

## Comment vérifier

Lancer l'admin de dev depuis le worktree, parcourir chaque écran en clair et sombre,
rétrécir pour le mobile. Comparer au visuel de la maquette Cockpit.
