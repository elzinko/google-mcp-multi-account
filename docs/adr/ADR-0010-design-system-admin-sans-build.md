# ADR-0010 — Un design system pour l'admin, sans framework ni build

**TL;DR.** L'admin fabrique son HTML en collant des chaînes de texte, sans couche
« composant » ni échelle d'espacement/typo. Pour la mettre en système sans trahir la
contrainte « zéro dépendance / 100 % local », on pose quatre briques, du bas vers le
haut : (1) des **tokens CSS** d'échelles, (2) une fonction ``html`` `` qui **échappe par
défaut** plus un mince jeu de **fonctions-composants** vanilla, (3) un **micro-routeur**
qui formalise les vues, (4) une **bascule liste/vignettes** réutilisable. On déroule
écran par écran, pilote = la page Sessions.

Statut : **proposé** (2026-08-30). Les specs visuelles vivent dans
`docs/design/design-system-admin.md` ; cet ADR porte la structure.

## Contexte

Tout le front tient dans `admin/index.html` (~1960 lignes : `<style>`, HTML, JS vanilla).
Le rendu passe par des fonctions `render*()` qui **concatènent des chaînes** posées en
`innerHTML`. Contrainte forte du projet : pas de bundler, pas de npm côté front, tout
local. Les couleurs sont déjà en variables CSS (clair/sombre) ; le reste (espacement,
typo, arrondis) est en dur et dérive.

Cinq faits structurels rendent une passe « pro » pénible :

1. **Rendu par concaténation** → échappement à la main (`esc()`, `attr()`), à réappeler à
   chaque feuille ; un oubli = injection.
2. **Pas de couche composant** : le même chip / badge / avatar est réécrit dans 4
   fonctions. Deux helpers seulement (`lockChip`, `portChip`) sont extraits — la preuve
   que le motif est utile, et qu'il manque partout ailleurs.
3. **Pas de token d'échelle** : 13 tailles de police, ~10 arrondis, paddings ad hoc.
   Aucun « bouton unique » à tourner pour resserrer le rythme visuel.
4. **Vue mêlée au rendu** : `VIEW` est réassigné *dans* les `render*()`. Rendre a l'effet
   de bord de naviguer. Sessions est déjà une exception codée à la main (early-return,
   timer et diff dédiés).
5. **Modales imbriquées** → drapeaux de reprise (`zonesResumePolicy`…) pour rouvrir la
   modale parente.

Le décompte du cadenas patche déjà `textContent` en place plutôt que de re-rendre, pour
ne pas détruire le DOM : l'équipe sait que le rerender casse focus/scroll et code
l'exception à la main.

## Décision

Quatre briques, dépendances dirigées vers le bas (une page dépend des composants et des
tokens ; jamais l'inverse).

1. **Tokens CSS d'échelles.** Étendre `:root` : `--sp-*`, `--fs-*`, `--r-*`, `--fw-*`,
   `--elev-*`. Neutres au thème → le bloc sombre ne redéfinit **que** des couleurs.

2. **``html`` `` + fonctions-composants.** Une *tagged template* (~15 lignes) qui échappe
   chaque interpolation par défaut, avec un marqueur explicite pour les fragments déjà
   sûrs. Elle supprime la classe de bug « j'ai oublié `esc()` ». Par-dessus, un module
   `ui.*` de fonctions **pures string→string** (`chip`, `badge`, `card`, `avatar`,
   `iconBtn`, `pageHeader`) — donc testables sous `node`, sans jsdom.

3. **Micro-routeur.** Extraire `go(mode, params)` qui fixe `VIEW`, appelle `syncChrome`,
   dispatche vers le bon `render*`. Les `render*` cessent de muter `VIEW`. Un registre de
   poll par route remplace les trois boucles ad hoc. Règle : *une surface est une **page**
   si elle a son propre flux de données / sa cadence de rafraîchissement ; sinon c'est une
   **modale**.* Pages = liste, détail, sessions, et **Setup** (candidat à promouvoir).

4. **Bascule liste/vignettes.** Préoccupation *de page*, pas d'item : `VIEW.layout`
   persisté en `localStorage`, la page choisit entre `accountRow()` et `accountCard()`
   sur un même view-model. Branchée dans l'en-tête de page, pas dans le renderer d'item.

Séquence : fondations (tokens) → couche composant → écran par écran, pilote = Sessions.

## Options considérées

- **Web Components natifs (`customElements`) pour tout** — *rejeté pour l'instant*. Vrai
  encapsulage et mises à jour chirurgicales, mais changement de paradigme surdimensionné
  pour un POC mono-dev. **Réservé** aux 2 widgets vraiment pénalisés par le rerender
  (cadenas à décompte, carte de session) *si* la douleur persiste après P1.
- **`<template>` + `cloneNode`** — *rejeté*. Échappement auto via `textContent`, mais
  remplissage impératif verbeux qui compose mal pour listes/variantes et jure avec le
  modèle « innerHTML remplacé en bloc ».
- **Micro-framework via CDN (lit-html, Alpine, Preact)** — *rejeté*. Viole frontalement
  « zéro dépendance / pas de npm front ».

## Conséquences

- **+** Un seul endroit pour le rythme visuel : la passe « pro » devient une édition de
  variables.
- **+** L'échappement cesse d'être un risque diffus (``html`` `` par défaut).
- **+** Migration écran par écran, sans big-bang ; chaque tranche livrable seule.
- **−** Coût d'amorçage (tokens + helpers) avant tout gain visible.
- **−** Discipline à tenir : aucune couleur/espacement hors token. Garde-fou : grep en
  revue.

**Risques & garde-fous.** Thème sombre : invariant « le bloc dark ne redéfinit que des
couleurs ». Reduced-motion : ne pas animer en JS. Focus des `<dialog>` : un mini
gestionnaire de pile de modales retire les drapeaux de reprise. **No-layout-shift** (le
vrai danger) : avant un rerender complet, capturer/restaurer `document.activeElement` et
ne pas re-rendre tant qu'une modale est ouverte au-dessus de la liste. Tests : le front
n'est **pas** couvert (`scripts/test.sh` teste l'API seule) ; filet léger = exécuter les
fonctions pures (dont ``html`` `` et `ui.*`) sous `node` dans `test.sh`, avec un test
d'injection `"><script>`. Playwright différé (ajoute un navigateur, surdimensionné).
