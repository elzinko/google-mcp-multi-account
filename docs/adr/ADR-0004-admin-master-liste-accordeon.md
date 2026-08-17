# ADR-0004 — Admin : liste-maître → page de détail, sans routeur

Statut : **accepté** — implémenté (fiche 0036, maquette v11) · révisé 2026-07-28 · Portée : `admin/index.html` + `admin/server.js`

> **Ratification 2026-07-28 (implémentation, maquette v11).** La forme **accordéon**
> (`<details>/<summary>`) d'origine est **abandonnée** au profit d'une **liste-maître →
> page de détail** : un swap d'état DOM (`VIEW = {mode:'list'|'detail'}`, fonctions
> `renderList` / `renderDetail`), **toujours sans routeur ni URL**. La décision 1 ci-dessous
> est donc révisée en ce sens ; les figures 1-2 illustrent l'exploration accordéon initiale
> et valent pour l'esprit (deux états, aucune navigation), pas pour la forme finale.
>
> **Écarts assumés à la ratification** (par rapport aux décisions 2 et 3 telles qu'écrites) :
> - **Décision 2** — l'édition des zones vit dans le **dialogue Zones** existant (bouton
>   « Zones… » sur la ligne Drive du détail), qui porte déjà les actions par zone
>   (prolonger / révoquer / ajouter), plutôt qu'en lignes éditables inline dans le panneau.
>   Fonction identique, forme = modale réutilisée (zéro dépendance, pas de ré-écriture).
> - **Décision 3** — le serveur expose les **flags de policy bruts** (`/api/profiles` →
>   `policy`) ; le front en **dérive** les libellés de droits (`capsHtml`, table `SVCDEF`).
>   L'invariant tenu est l'essentiel : **le front n'affirme jamais un droit en dur** — chaque
>   « vert / rouge » vient d'un flag réel. Le mapping flag → libellé (partagé, une seule table)
>   vit côté front plutôt que côté serveur ; la bascule 0037 (corbeille = suppression) n'agira
>   toujours que sur un flag serveur (`delete`), pas sur le front.
Fiches liées : 0036 (clarté des cartes), 0037 (sémantique de la suppression en zone)

> **TL;DR** — La page web d'administration (qui gère les comptes Google connectés) abandonne les cartes dépliables « accordéon » au profit d'une liste cliquable qui bascule vers une page de détail par compte — sans adresse URL ni routeur, juste un changement d'état à l'écran — afin de rester une page unique sans dépendance ; et les droits affichés pour chaque compte sont **dérivés côté navigateur** à partir des flags de policy bruts servis par le serveur (`/api/profiles`), plutôt qu'écrits en dur dans la page.

## Contexte

L'admin web local est **une seule page** HTML/CSS/JS vanilla (aucun framework,
aucun routeur, aucun build), servie par `admin/server.js` en **Node stdlib pur
(zéro dépendance)**. Les données arrivent en JSON (`GET /api/profiles`), les
actions partent en `POST /api/<alias>/<action>` vers `bin/mag`.

On veut passer d'une simple liste de cartes à :
(a) une vue d'**ensemble** (tous les comptes, résumés) ;
(b) un **détail** par compte où les zones d'écriture Drive sont visibles et
**modifiables en ligne** (par zone : prolonger, révoquer, modifier).

Deux formes possibles : master-liste seule avec **expansion in-place**, ou
**master + vue de détail** (qui impose une forme de navigation/routing).

Contrainte transverse : le texte d'avertissement affiché à la pose d'une zone
(« le LLM pourra créer/modifier/corbeiller… ») **dépend d'une décision de policy
non tranchée** (fiche 0037 : corbeille = suppression ? racine de zone immuable ?).
L'UI ne doit pas figer cette décision.

## Décision

**1. Liste-maître → page de détail, par swap d'état DOM** (~~accordéon
`<details>/<summary>`~~, révisé — cf. ratification en tête). Un seul état
`VIEW = {mode:'list'|'detail', alias}` et deux chemins de rendu (`renderList` /
`renderDetail`) dans le même `#cards` : la liste montre une ligne par compte
(interrupteur · cadenas · décompte · chevron) ; cliquer une ligne rend la page de
détail (droits par appli, zones, zone de danger) ; « ‹ Comptes » revient à la
liste. **Toujours pas de routeur** — ni hash côté front, ni route HTML côté
serveur : une simple bascule d'état, un seul artefact.

**2. L'édition des zones vit dans le panneau déplié de la carte.** Chaque zone
est une ligne du panneau portant ses propres actions (prolonger / révoquer /
modifier) ; le résumé replié (`1 temporaire · expire dans 1 h 58`) reste la vue
condensée. Le bouton « ajouter une zone » est en pied de panneau.

**3. L'avertissement de zone est une DONNÉE fournie par le serveur, pas une
chaîne codée dans le front.** `server.js` (qui détient la policy) expose, par
service et par profil, la liste des **verbes effectivement autorisés** (créer,
modifier, corbeiller…) dérivée des flags de policy. Le front **rend** cette
liste ; il n'affirme jamais un verbe en dur.

```mermaid
stateDiagram-v2
    direction LR
    [*] --> Liste
    state "Vue d'ensemble (a)\nN cartes repliées : connexion · accès · résumé zones" as Liste
    state "Carte dépliée (b)\nzones éditables : prolonger / révoquer / modifier · + ajouter" as Detail
    Liste --> Detail : clic sur une carte (details/summary natif)
    Detail --> Liste : re-clic (repli)
    Detail --> Detail : action zone -> POST /api/<alias>/<action> -> re-render
    note right of Detail
        Un seul panneau ouvert à la fois (accordéon).
        Aucune URL, aucun routeur : simple bascule d'état DOM.
    end note
```

*Figure 1 — Modèle d'interaction : la vue d'ensemble et le détail sont deux
états de la MÊME carte (repliée / dépliée), reliés par `<details>` natif ; aucune
navigation ni URL n'est introduite.*

```mermaid
flowchart TD
    subgraph FRONT["admin/index.html (rendu)"]
        A["Panneau zone d'un compte"]
    end
    subgraph BACK["admin/server.js (détient la policy)"]
        B["Descripteur de capacité\nverbes autorisés = f(flags policy)"]
    end
    subgraph OPEN["fiche 0037 (décision NON tranchée)"]
        C["corbeille = suppression ?\nracine de zone immuable ?"]
    end
    A -->|"lit et affiche la liste de verbes"| B
    C -.->|"fera basculer un flag, plus tard"| B
    A -. "ne connaît PAS" .-x C

    classDef front fill:#eeedfe,stroke:#534ab7,color:#222;
    classDef back fill:#e1f5ee,stroke:#0f6e56,color:#222;
    classDef open fill:#faeeda,stroke:#854f0b,color:#222;
    class A front
    class B back
    class C open
```

*Figure 2 — Découplage : le front (violet) dépend d'une abstraction, le
descripteur de capacité (vert) ; la décision 0037 (ambre) n'agira que sur un flag
serveur. Trait plein = dépendance assumée ; pointillé = influence future ; croix
= le front n'a aucun lien direct avec 0037. Trancher 0037 ne touchera pas
`index.html`.*

## Options rejetées

- **Master + vue de détail avec routeur hash** (`#/profile/perso`) : impose un
  mini-routeur maison (parse de `location.hash`, swap de vue, gestion du bouton
  retour) + deux chemins de rendu à synchroniser. YAGNI pour 5–20 comptes.
- **Route HTML serveur `/profile/<alias>`** : duplique la mise en page, un
  aller-retour réseau par compte, casse la page unique.
- **Détail en modale `<dialog>`** : dep-free mais enferme sur un compte, empêche
  de balayer/comparer les zones entre comptes ; plus lourd que l'inline.
- **Avertissement codé en dur dans le front** (état actuel de la maquette) :
  couple l'UI à la sémantique 0037 encore ouverte.

## Conséquences

- **+** Zéro dépendance nouvelle ; un seul chemin de rendu ; expansion accessible
  et gratuite (`<details>` natif, déjà utilisé pour le menu ⋯).
- **+** Passe à l'échelle par le scroll ; **un seul panneau ouvert à la fois**
  garde le DOM petit et l'attention focalisée.
- **+** 0037 pourra être tranchée sans toucher `index.html` : seul le descripteur
  de verbes côté `server.js` change.
- **−** Panneau déplié long sur petit écran → mitigé par l'accordéon (un ouvert)
  et un `scrollIntoView` à l'ouverture.
- **−** Petit ajout backend : exposer les verbes autorisés par service/profil
  dans `/api/profiles` (ou un point dédié). C'est le bon domicile — la policy
  vit côté serveur (DIP).
- À 20+ comptes, prévoir un filtre/recherche en tête de liste (cheap, plus tard) ;
  hors périmètre POC.
