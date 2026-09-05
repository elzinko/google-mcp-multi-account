---
id: 0097
title: Finir la migration des dialogues et écrans restants vers le design system Cockpit
type: feature
priority: P1
product: google-mcp-multi-account
version:
epic: 0060
status: shipped
ready: 2026-09-03
pr: "#133"
created: 2026-08-30
---

> **Fusion 0097 + ex-0100 (2026-09-03).** Cette fiche absorbe l'ancienne 0100 (« déploiement
> écran par écran + contraste AA »). Deux morceaux de son périmètre d'origine sont **déjà
> livrés par la refonte Cockpit (#128)** et sortis du scope : les composants transverses
> (pastille `.ck-cap`, callout `.ck-callout`, boutons `.ck-btn`) et la passe **contraste AA**
> (`--mut` assombri, `.b-mut` corrigé). Reste **un seul chantier** : faire passer les
> **dialogues et écrans encore en ancien HTML** sous le design system Cockpit.

## En clair

La refonte Cockpit a migré les grands écrans (Comptes, Détail, Sessions, Journal, navigation).
Mais **plusieurs dialogues et écrans secondaires** utilisent encore l'ancien HTML : la modale
**Policy** (faux onglets, notes en prose), la gestion des **Zones**, l'écran **Setup/IAM**,
l'écran **Dev**. Et la **coquille de modale unifiée** (`.ck-modal` : en-tête / corps
scrollable / pied collant) existe dans le CSS mais **n'est appliquée à aucun `<dialog>`** — les
~15 dialogues gardent chacun leur balisage. On finit le travail : une seule coquille de modale,
et les écrans restants au design system.

Référence : [`docs/design/design-system-admin.md`](../docs/design/design-system-admin.md) §2, §3 et §5, ADR-0010.

> **À séquencer après [`0107`](0107-vue-compte-droits-sur-place.md).** 0107 **supprime la
> modale Policy** de la page compte (droits édités sur place). On ne migre donc que les
> dialogues qui **subsistent** après 0107 — pour ne pas repeindre une modale qu'on retire.

## Contexte / problème

- La coquille `.ck-modal` (`.ck-modal__head/body/foot/scrim`) est **définie** en CSS mais
  **inutilisée** : les ~15 `<dialog>` gardent `dlg-confirm` / `dlg-policy` / un balisage nu,
  sans pied collant homogène.
- La modale **Policy** (`dPolicy`) garde de **faux onglets** (`class="tabs"`) au lieu de
  préréglages segmentés, et ses notes sont en prose (`class="note"`) au lieu de callouts.
- La gestion des **Zones** (`dZones`) reste un empilement de dialogues.
- **Setup/IAM** (`renderSetup`) et **Dev** utilisent encore `class="note"` / `badge b-ok`
  (anciennes classes), non migrés.

## Proposition

- **Coquille modale unique** : appliquer `.ck-modal` (en-tête / corps scrollable / pied
  toujours visible) aux `<dialog>` génériques (confirmation, et ceux qui subsistent après 0107).
- **Policy** (ce qui subsiste après 0107) : préréglages en **segmenté** (fin des faux onglets),
  notes en **callouts** `.ck-callout`.
- **Zones** : panneau **inline** plutôt qu'empilement de dialogues.
- **Setup / Dev** : carte + segmenté, classes `.ck-*` (fin de `class="note"` / `badge b-ok`).

## Critères d'acceptation

- [ ] Tous les `<dialog>` subsistants utilisent la coquille `.ck-modal` (en-tête / corps / pied collant), focus clavier préservé.
- [ ] Policy (si elle subsiste après 0107) : préréglages segmentés (plus de faux onglets), notes en callouts.
- [ ] Zones : panneau inline (plus d'empilement de dialogues).
- [ ] Setup et Dev migrés au design system (plus de `class="note"` / `badge b-ok`).
- [ ] Rendu clair ET sombre corrects ; zéro dépendance ajoutée ; `./scripts/test.sh` au vert.

## Comment vérifier

Ouvrir chaque dialogue subsistant (confirmation, Zones, et Policy si elle existe encore) : même
coquille, pied collant, focus préservé. Ouvrir Setup et Dev : classes `.ck-*`, plus d'anciennes
notes/badges. Contrôler clair et sombre.

## Déjà livré par Cockpit (#128) — hors périmètre

- Composants transverses : pastille de droit `.ck-cap` (icône + couleur), callout
  `.ck-callout`, boutons `.ck-btn` (matrice taille × variante). *(ex-0097)*
- Passe **contraste AA** : `--mut` assombri (`#63625d`), `.b-mut` corrigé sur `--bg`. *(ex-0100)*
- Détail : un seul bouton « Configurer les droits ». *(ex-0100)*
