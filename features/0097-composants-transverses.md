---
id: 0097
title: Composants transverses — pastille de droit accessible, callout, boutons, coquille modale
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

On unifie les objets qu'on retrouve partout, aujourd'hui réécrits à la main dans plusieurs
fonctions. Quatre chantiers : une **pastille de droit accessible** (icône + couleur, pas
juste la couleur), un **callout** d'aide/alerte, un **système de boutons** nommé, et une
**coquille de modale unique** (en-tête / corps / pied fixe).

Référence : [`docs/design/design-system-admin.md`](../docs/design/design-system-admin.md) §2 et §3, ADR-0010 (brique 2).

## Contexte / problème

Le chip, le badge, l'avatar sont réémis dans 4 fonctions différentes. La pastille de droit
(`.cap`) n'encode le sens que par la couleur (défaut d'accessibilité). Les modales ont
trois patterns (confirm structurée, policy à pied collant, ~11 dialogues génériques sans
pied fixe). Deux styles « danger » non nommés.

## Proposition

- `ui.*` : `chip()`, `badge()`, `avatar()`, `iconBtn()`, `card()`, `pageHeader()`
  (fonctions pures, sur ``html`` ``).
- Pastille de droit : vraie pilule `.cap.y` (✓) / `.cap.n` (✗), sens porté par icône + couleur.
- Callout `--info/--warn/--bad` remplaçant `.zwarn` et les ⚠️ en prose.
- Boutons : matrice tailles (`sm`/`md`) × variantes (`surface`/`primary`/`danger-quiet`/
  `danger`/`ghost`), en nommant quiet (déclencheur) vs plein (irréversible).
- Coquille modale unique : en-tête / corps scrollable / pied toujours visible ; généraliser
  aux dialogues génériques.

## Critères d'acceptation

- [ ] La pastille de droit distingue accordé/refusé **sans** la couleur (icône présente).
- [ ] Un seul composant carte/bouton/modale, réutilisé (plus de recopie inline).
- [ ] Contraste AA vérifié en clair et sombre sur les nouveaux composants.
- [ ] Aucune régression focus/clavier des modales.

## Comment vérifier

Ouvrir détail (pastilles), une confirmation et le dialogue policy : même coquille, pied
fixe, pastilles avec glyphe. Test daltonien simulé (niveaux de gris) : accordé/refusé
restent distincts.
