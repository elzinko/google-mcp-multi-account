# Design system — admin google-multi-account

## En clair

L'admin est déjà propre sur le fond : bonnes couleurs, thème clair/sombre soigné, focus
et « animations réduites » respectés. Le problème n'est pas le goût, c'est la **mécanique
invisible** : les tailles de texte, les espacements et les arrondis sont posés à la main,
valeur par valeur, sans échelle commune. On compte 13 tailles de police, une dizaine
d'arrondis, trois familles de « cartes » qui ne se ressemblent pas.

Ce document fixe la **cible** : cinq échelles chiffrées (espacement, typo, arrondis,
poids, élévation) et les specs de trois objets transverses (la carte, la pastille de
droit, la modale). On ne repeint pas l'app — on la **met en système**. On l'applique
ensuite écran par écran, en commençant par Sessions.

> Contrainte du projet : **zéro dépendance, 100 % local, pas d'outil de build**. Tout
> tient en variables CSS et en vanilla JS. La couche technique qui porte ce système est
> décrite dans l'ADR-0010.

---

## 1. Les échelles (tokens)

À poser dans `:root` (`admin/index.html`), **au-dessus** des règles de composants. Les
tokens d'espacement, typo et arrondis sont **neutres au thème** : le bloc
`@media (prefers-color-scheme: dark)` continue de ne redéfinir **que des couleurs**.

### Espacement (base 4)

```
--sp-1: 4px   --sp-2: 8px   --sp-3: 12px  --sp-4: 16px
--sp-5: 20px  --sp-6: 24px  --sp-8: 32px  --sp-10: 40px
```

Remplace la quinzaine de valeurs actuelles (7, 9, 10, 11, 13, 14, 18, 22…). Carte =
padding `--sp-4` ; gap interne `--sp-2`/`--sp-3` ; marge de section `--sp-4`/`--sp-6` ;
padding de modale `--sp-5`.

### Typographie (6 tailles au lieu de 13)

```
--fs-caption: 12px   /* aides (.note), légendes, badge */
--fs-small:   13px   /* boutons small, pastille de droit */
--fs-body:    15px   /* corps, cases à cocher */
--fs-strong:  16px   /* identité (email/alias), nom de service */
--fs-h2:      18px   /* titres de modale (unifie 17 et 18) */
--fs-h1:      20px   /* titre header + titre de page */
```

Interlignes : `--lh-tight: 1.3` (titres), `--lh-body: 1.5` (texte).

Poids : `--fw-normal: 400`, `--fw-medium: 500`, `--fw-semibold: 600`. **Abandonner le
700.** Aujourd'hui les emails sont en 700 et crient plus fort que les titres en 600 —
l'identité en 600 suffit.

### Arrondis (6 au lieu de ~10)

```
--r-xs: 6px   /* input, chip, bouton small */
--r-sm: 8px   /* bouton */
--r-md: 10px  /* carte imbriquée (session, dev), cadenas */
--r-lg: 12px  /* carte / rangée de 1er niveau */
--r-xl: 16px  /* modale (unifie 14 et 16) */
--r-pill: 999px
```

### Élévation (3 niveaux nommés)

```
--elev-0: none                        /* cartes : liseré seul — parti pris à garder */
--elev-1: 0 8px 24px rgba(0,0,0,.16)  /* popover, toast */
--elev-2: 0 20px 48px rgba(0,0,0,.28) /* modale (aujourd'hui : rien) */
```

---

## 2. Corrections d'accessibilité (au-delà du goût)

Trois points qui ne sont pas cosmétiques :

1. **La pastille de droit encode le sens par la seule couleur.** Aujourd'hui `.cap` est
   du texte vert (accordé) ou rouge (refusé), sans autre marque. Un daltonien ne
   distingue pas les deux. → ajouter un **glyphe** ✓ / ✗ (voir §3).
2. **Le gris `--mut` passe le contraste AA de justesse en clair** (~4,55:1 pour 4,5
   requis). → assombrir `--mut` clair vers ~`#63625d`. Ne pas toucher au `--mut` sombre
   (confortable).
3. **Le badge `.b-mut` est quasi invisible** sur une carte de session (même fond
   `--bg`). → fond distinct, ex. `color-mix(in srgb, var(--txt) 6%, transparent)`.

---

## 3. Les composants

### La carte (token unique)

Fond `--card`, liseré `--line`, arrondi `--r-lg`, padding `--sp-4`, `--elev-0`. Variante
imbriquée `.card--nested` (arrondi `--r-md`, padding `--sp-3`). **Migrer `.prow`,
`.sess-card`, `.devcard` dessus** → fond `--card` partout. Fin de l'incohérence
« trois cartes, trois recettes » : aujourd'hui les cartes de session ont le même fond
que la page et ne tiennent que par le liseré.

**Carte de session à hauteur régulière** (cause du rendu en escalier : pas de hauteur
mini, actions non ancrées) :

```
.sess-card    { display:flex; flex-direction:column; min-height:132px; gap:var(--sp-2); }
.sess-actions { margin-top:auto; }   /* actions collées en bas → cartes alignées */
```

### La pastille de droit (accessible)

Vraie pilule, icône + label, le sens ne repose plus sur la couleur :

```
.cap    { display:inline-flex; align-items:center; gap:4px; font-size:var(--fs-small);
          font-weight:var(--fw-semibold); padding:2px 8px; border-radius:var(--r-pill); }
.cap.y  { color:var(--ok);  background:var(--okbg); }   /* + ✓ */
.cap.n  { color:var(--bad); background:var(--badbg); }  /* + ✗ */
```

### Le bouton (matrice tailles × variantes × états)

- Tailles : `sm` (hauteur 28, `--fs-small`) ; `md` (hauteur 34, `--fs-body`).
- Variantes : `surface` (défaut), `primary` (accent), `danger-quiet` (contour — pour
  **déclencher** une confirmation), `danger` (plein — pour l'**action irréversible**),
  `ghost` (items de menu). Nommer la distinction quiet/plein (aujourd'hui `.danger` vs
  `.danger-solid`, sensée mais non documentée).
- États hover/active/disabled/loading : **déjà tous présents**, à conserver.

### La modale (coquille unique)

Trois zones : en-tête (titre + icône optionnelle) / corps scrollable / **pied toujours
visible, actions à droite**. Généraliser le pied collant de la policy aux ~11 dialogues
génériques (aujourd'hui leur pied scrolle avec le contenu). Arrondi `--r-xl` partout. Les
confirmations restent une spécialisation (icône + puce compte).

### Le callout (aide/alerte)

Remplace le mélange `.note` (texte gris) + `.zwarn` (seul encadré existant) :

```
.callout        { display:flex; gap:var(--sp-2); padding:var(--sp-3);
                  border-radius:var(--r-md); border:1px solid; font-size:var(--fs-caption); }
.callout--info  { color:var(--acc);  background:var(--accbg);  }
.callout--warn  { color:var(--warn); background:var(--warnbg); }
.callout--bad   { color:var(--bad);  background:var(--badbg);  }
```

Cible : les avertissements en prose avec ⚠️ inline deviennent des callouts.

### La bascule liste / vignettes (façon Finder)

Contrôle segmenté réutilisable, **distinct des onglets** (`.tabs`), état persisté en
`localStorage` (modèle déjà en place : la « Vue dense » du journal) :

```
.viewtoggle { display:inline-flex; border:1px solid var(--line); border-radius:var(--r-sm); overflow:hidden; }
.viewtoggle button[aria-pressed="true"] { background:var(--accbg); color:var(--acc); }
```

- **Vignettes** = la grille actuelle, carte régulière.
- **Liste** = une rangée par item (id · badges · capacités inline · actions), dense et
  **triable**.
- S'applique d'abord à **Sessions**, avec un **tri** (par client, par dernière activité,
  par nombre de capacités) — absent aujourd'hui.

> Le même contrôle segmenté sert à corriger les **préréglages de policy**, aujourd'hui
> déguisés en onglets alors que ce sont des actions.

---

## 4. Ce que le système ne change pas

La qualité déjà là : états de boutons complets, cadenas animé avec décompte, thème
clair/sombre, respect de `prefers-reduced-motion`, piège-à-focus des modales. On nomme et
on systématise ; on ne réécrit pas ce qui marche.

---

## 5. Application par tranches

Voir les fiches sous l'épic **0060** (`features/`) :

1. **Fondations** (P0, aucun changement visuel visé) : les cinq échelles + la carte unifiée.
2. **Socle rendu sûr** (P0) : une fonction d'échappement par défaut + un filet de tests.
3. **Composants transverses** (P1) : pastille accessible, callout, boutons, coquille modale.
4. **Micro-routeur** (P1) : formaliser les vues (pages vs modales).
5. **Sessions — tranche pilote** (P1) : cartes régulières, bascule liste/vignettes, tri.
6. **Déploiement** (P2) : écran par écran (détail, policy, liste, dev, setup) + passe contraste AA.
