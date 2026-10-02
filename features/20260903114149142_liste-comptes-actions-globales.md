---
id: "20260903114149142"
title: Barre d'actions globales au-dessus de la liste des comptes (tout verrouiller / déverrouiller, ± temps)
type: feature
priority: P2
product: google-mcp-multi-account
version:
epic: 0060
status: idea
ready:
pr:
created: 2026-09-03
---

## En clair

Chaque compte a déjà sa **puce cadenas** à droite de sa ligne. Un clic verrouille ou déverrouille.
Quand le compte est déverrouillé, un **+** et un **−** rallongent ou raccourcissent le temps qui
reste. Pour agir sur plusieurs comptes aujourd'hui, il faut le faire **un par un**.

On veut une **barre d'actions au-dessus de la liste**, sans fond visible, **alignée à la verticale**
de la colonne des puces cadenas. Elle applique les mêmes gestes à **tous les comptes d'un coup** :
tout verrouiller, tout déverrouiller, et **± du temps** sur tous les comptes déverrouillés.

Au passage, on corrige un irritant : les boutons **+** et **−** restent **toujours affichés**.
Aujourd'hui ils n'apparaissent qu'au survol, donc on ne devine pas qu'ils existent.

Le « tout verrouiller » global **existe déjà** (bouton livré par la PR #112, fiche
[`0063`](done/0063-tout-verrouiller-icone-modale.md)). Cette fiche le **réutilise** dans la barre et
**ajoute ce qui manque** : le « tout déverrouiller » et le **± temps** global.

## Contexte / Problème

La puce par compte est le composant `lockChip` (`admin/index.html:2499`), rendu à droite de chaque
ligne de compte (`.prow`). Ses gestes :

- verrou / déverrou : `lockClick(alias)` (`admin/index.html:2754`) ;
- temps : `prolong(alias)` (`admin/index.html:2795`) et `shorten(alias)` ;
- ajustement fin ±30 min : `openRelock` + la modale `.dlg-relock-adjust` (`admin/index.html:231`).

Deux manques et un irritant :

1. **Pas d'action groupée.** Avec plusieurs comptes, verrouiller / déverrouiller / ajuster le temps
   se fait ligne par ligne. Répétitif.
2. **Un seul geste global existe, incomplet.** Le « tout verrouiller » est là :
   `openLockAll()` → modale `dLockAll` → `doLockAll()` → `POST /api/lockall`
   (`admin/index.html:2869`). Il **manque** le « tout déverrouiller » et le **± temps** global. Et ce
   bouton vit dans un rail d'outils, **pas** dans une barre alignée sur la colonne des puces.
3. **Les boutons +/− sont invisibles au repos.** Les `.cd-act` sont à `opacity:0` par défaut
   (`admin/index.html:264`) et ne passent visibles qu'au survol / focus (`admin/index.html:268`).
   La fonctionnalité ne se voit donc pas tant qu'on ne survole pas la puce.

**Valeur.** Un poste de commande unique en haut de la liste : un geste pour verrouiller ou
déverrouiller tout, un geste pour donner ou reprendre du temps à tout le monde. Et une
fonctionnalité (± temps) qui se **voit** enfin.

## Proposition

**A. Barre d'en-tête « fantôme » au-dessus de la liste.**
Sans fond ni bordure, alignée **verticalement** sur la colonne des puces cadenas (même gabarit
qu'une `lockchip`, à la place où les puces des comptes tombent). Elle **réutilise** le composant
existant plutôt que d'en refaire un.

**B. Cadenas global : tout verrouiller / tout déverrouiller.**
Le « tout verrouiller » réutilise l'existant (`openLockAll` → `/api/lockall`). On ajoute son
**symétrique** : « tout déverrouiller » (les comptes verrouillés connectés).

**C. + / − global : ± temps sur tous les comptes déverrouillés.**
Applique `prolong` / `shorten` à **tous les comptes ayant une fenêtre active**, en une action.

**D. Boutons + et − toujours visibles.**
Retirer l'`opacity:0` au repos des `.cd-act` (au moins dans la barre globale) pour que le geste se
voie sans survoler.

**Portée du « tous ».** Le ± temps ne touche **que les comptes déverrouillés** (fenêtre active). Un
compte verrouillé n'est **pas** déverrouillé en douce par un « + temps ».

### À trancher au grooming (pas décidé ici)

- **Tout déverrouiller** : quelle durée ? Réutiliser la modale « unlock » par compte, ou déverrouiller
  à une durée standard ?
- **± temps global** : même pas que par compte (±30 min) ; via une boucle client sur les comptes
  déverrouillés, ou des routes dédiées (`/api/unlockall`, `/api/*-all`) ?
- **Confirmation d'impact** : garder une modale pour « tout déverrouiller » (comme « tout verrouiller »
  a la sienne) ?
- **Portée du « toujours visible »** : seulement la barre globale, ou aussi chaque puce compte ?

## Critères d'acceptation

- [ ] Une barre d'actions apparaît **au-dessus de la liste** des comptes, **sans fond visible**, alignée verticalement sur la colonne des puces cadenas.
- [ ] Un geste « tout verrouiller » verrouille tous les comptes déverrouillés (réutilise `/api/lockall`).
- [ ] Un geste « tout déverrouiller » déverrouille les comptes verrouillés connectés.
- [ ] Les boutons **+** / **−** de la barre ajoutent / retirent du temps à **tous les comptes actuellement déverrouillés**, en une seule action.
- [ ] Les boutons **+** et **−** sont **visibles en permanence** (plus seulement au survol).
- [ ] Le ± temps ne touche **que** les comptes déverrouillés : aucun compte verrouillé n'est déverrouillé en douce.
- [ ] Rendu **clair ET sombre** corrects ; **zéro dépendance** ajoutée ; `./scripts/test.sh` au vert.

## Comment vérifier

Avec au moins **deux comptes connectés** : en déverrouiller un manuellement, laisser l'autre
verrouillé.

- Cliquer le **+** de la barre → le temps du compte déverrouillé augmente ; le verrouillé **reste**
  verrouillé.
- « **Tout déverrouiller** » → les deux passent déverrouillés.
- « **Tout verrouiller** » → les deux reviennent verrouillés.
- Vérifier que **+** et **−** sont visibles **sans** survoler la puce.
- Contrôler en **clair** et en **sombre**.

## Notes

- **Réutilise / consolide** le « Tout verrouiller » livré par la PR #112 — fiche
  [`0063`](done/0063-tout-verrouiller-icone-modale.md) (`shipped`) : `openLockAll` / `doLockAll` /
  `dLockAll`, `POST /api/lockall` (`admin/index.html:2869`).
- **Composant réutilisé** : `lockChip` (`admin/index.html:2499`) ; gestes `lockClick`
  (`admin/index.html:2754`), `prolong` (`admin/index.html:2795`), `shorten` ; modale ±30 min
  `openRelock` / `.dlg-relock-adjust` (`admin/index.html:231`).
- **Irritant ergonomie** : `.cd-act` à `opacity:0`, visibles seulement au survol
  (`admin/index.html:264` et `admin/index.html:268`).
- **Voisins, mais distincts** : [`0107`](0107-vue-compte-droits-sur-place.md) porte sur la page
  **détail d'un compte** ; [`0104`](0104-app-shell-responsive-mobile.md) sur le compte tenant sur une
  ligne (mobile). Ici, c'est la **barre au-dessus de la LISTE**.
- **Épic** : [`0060`](0060-admin-ux-ui-refresh.md) (refonte admin UX).
