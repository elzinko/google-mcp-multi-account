---
id: 0107
title: Vue compte — piloter les droits sur place (remplacer la modale Policy) + nettoyer la liste
type: feature
priority: P1
product: google-mcp-multi-account
version:
epic: 0060
status: shipped
ready: 2026-09-03
pr: "#131"
created: 2026-09-03
---

## En clair

Aujourd'hui, pour changer les droits d'un compte, il faut ouvrir la page **Policy** — austère
et à part. On veut l'inverse : **régler les droits directement sur la page du compte**. Chaque **droit**
(lire Gmail, envoyer, créer dans Drive…) devient une bascule qu'on active ou coupe d'un clic, au
grain réel de la policy. Vert = autorisé, rouge = coupé (au lieu du texte barré actuel). La ligne Drive gagne un bouton « dossiers » à
droite, pour choisir les zones d'écriture permanentes. Au passage, on nettoie la liste des comptes :
vignettes en couleur, moins de texte, bouton « Connecter » en bas.

Fait suite aux retours de Thomas du 2026-09-03 sur la refonte Cockpit (PR #128). C'est du
**fonctionnel + UX**, distinct de la refonte visuelle. Voisin direct de la fiche
[`0106`](0106-vue-compte-orientee-sessions.md) (vue compte orientée sessions).

> **Rappel du modèle — à ne pas confondre.** La policy, c'est le **plafond** d'un compte : ce
> qui est *permis au maximum*. Elle n'ouvre aucune donnée toute seule. Chaque session doit
> ensuite **demander** son accès par un geste humain signé (élicitation,
> [ADR-0007](../docs/adr/ADR-0007-droits-par-session.md)). Éditer la policy sur la page du
> compte = régler ce plafond. Ça reste un **geste admin**, pas un octroi de session.

## Contexte / problème

La page d'un compte (`renderDetail`, `admin/index.html:2725`) affiche les droits en
**lecture**, via des pastilles par service (`ckCapsHtml`, `:2684`). Pour les changer, un bouton
« Configurer les droits » (`:2755`) ouvre la **modale Policy** (`dPolicy`, `:2165`, fonction
`openPolicy`). Deux reproches de Thomas :

1. C'est **incohérent** : on montre la config sur la page, mais il faut sauter dans une autre
   surface pour la modifier.
2. La modale Policy est **moche** et lourde (cases à cocher par service, JSON sous-jacent).

Sous la fiche, un paragraphe verbeux — « Retirer ce compte de l'outil — réversible (reconnexion
complète). » (`:2758`) — occupe de la place pour rien.

**Valeur.** On règle les droits **là où on les lit** : un aller-retour en moins, une surface en
moins à maintenir. La page compte devient le vrai poste de pilotage du plafond d'un compte, et la
liste dit d'un coup d'œil l'état de chacun (les 3 couleurs).

## Proposition

**A. Droits éditables sur place (remplace la modale Policy).**
Chaque service affiche ses **opérations** (Gmail : lire, brouillons, envoyer, modifier, supprimer,
réglages ; Drive : lire, créer, modifier, supprimer, partager…), et **chaque opération** est une
bascule cliquable — vert = autorisée, rouge = coupée. On reste au **grain réel de la policy**
(`gateway/default_policy.py` : un booléen par opération). **Pas** de bouton unique par service : il
activerait des opérations sensibles (envoyer, supprimer) ou en perdrait d'autrement autorisées, en
douce. La modale Policy disparaît ; un pli « avancé » (édition brute) reste pour les scopes rares.

**B. Bouton « dossiers » sur la ligne Drive — zones PERMANENTES uniquement.**
À droite de la ligne Drive, une icône ouvre la gestion des **zones permanentes** (la liste
`writeFolders` de la policy). Réutilise le **navigateur de dossiers** (`afPick` `:3360`).

> **Mutation zone-seule (piège relevé par la revue).** La route actuelle
> `/api/profiles/<alias>/drive-folder` n'est **pas** neutre : elle appelle `mag policy … allow`
> (`admin/server.js:827`), qui **crée le bloc Drive avec `create` et `update` à `true`**
> (`bin/mag:489`). Sur un compte dont la policy **omet** le bloc Drive (écriture *default-deny*),
> ajouter une zone **activerait deux opérations en douce** — l'inverse du grain par opération (A).
> Ajouter/retirer une zone doit donc être une **mutation `writeFolders` pure** qui **préserve** les
> flags d'opération existants (nouvelle route zone-seule), **pas** `policy allow`.

> **Piège relevé par la revue — ne pas réutiliser la branche « temporaire » du sélecteur.** Son
> option temporaire poste sur `/api/profiles/<alias>/grant` (`admin/index.html:3384`), qui appelle
> le `mag grant` **compte-large** (`admin/server.js:821`). La page compte **n'a pas de session** :
> y émettre un grant « temporaire » l'ouvrirait à **toutes** les sessions — l'inverse du modèle.
> Donc la page compte édite **le plafond** (zones permanentes) ; les grants **temporaires par
> session** restent dans la vue **Sessions** (icône dossier d'une session → `/api/sessions/<sid>/grant`,
> `openSessGrant` `:3055`).

Activer l'écriture met le compte en **mode zones** (`zonesOnly: true`, **jamais** wildcard). La
liste `writeFolders` peut rester **vide** : c'est le **défaut sûr** (`default_policy.py` la pose
vide). L'écriture est alors **refusée au niveau compte** ; chaque session obtient son accès par un
**grant de session temporaire**, **dans sa propre session** — pas depuis ici. On ne **force jamais**
une zone permanente pour autant.

**C. Icône pour configurer, pas un libellé.**
Remplacer le bouton texte « Configurer les droits » par une **icône** (roue crantée ou clé),
libellé au survol — cohérent avec les boutons-icônes de la page Sessions.

**D. « Retirer ce compte » = un bouton, pas un paragraphe.**
Supprimer la phrase longue. Un **bouton discret à droite** suffit ; **infobulle** pour le détail
(« réversible, reconnexion complète »). Garder la modale de confirmation (fiche
[`0061`](done/0061-deconnexion-modale-confirmation.md)).

**E. Liste des comptes : vignettes en couleur.**
Les tuiles d'état passent en couleur porteuse de sens :
**connectés = bleu**, **état ouvert / permissif = vert**, **état fermé / restreint = rouge**.
Réutilise le composant `.ck-stat` (`:1240`) en ajoutant des variantes de couleur (aujourd'hui :
neutre + `--warn`).

> **Arbitrage avec la fiche [`0106`](0106-vue-compte-orientee-sessions.md).** 0107 apporte le
> **système de couleur** ; 0106 décide **ce que comptent** ces vignettes. 0106 juge l'état
> « verrouillé / déverrouillé » **par compte** trompeur et veut le remplacer par un **compteur de
> sessions** (en gardant un indicateur « porte d'élicitation » ouverte/fermée). Donc : si 0107
> passe en premier, il colore les vignettes actuelles ; quand 0106 atterrit, il **redéfinit** leur
> sens et **réutilise** les mêmes couleurs — rien de jeté. En cas de conflit, **0106 prime sur la
> sémantique** de l'état compte ; 0107 garde la main sur le visuel et l'édition des droits.

**F. « Connecter un compte » en bas de la liste.**
Déplacer le CTA « + Connecter » **sous** la liste, à la suite. Compromis assumé : si beaucoup de
comptes, il faut scroller pour l'atteindre — peu probable dans cet usage perso.

## Décisions de conception (groomées 2026-09-03)

Les trois arbitrages ouverts à la capture sont tranchés.

- **Cliquer un service édite la policy — un geste admin sur le plafond.** On reste au **même
  niveau de confiance** que la modale Policy d'aujourd'hui. Ça **n'accorde rien à une session** :
  chaque session continue de demander son propre accès (ADR-0007). Donc aucun court-circuit du
  modèle par session. Le plafond ≠ l'octroi.
- **Un seul rouge « sécurité », réservé au verrou.** On garde le code couleur demandé : **vert =
  service autorisé**, **rouge = service coupé**. Mais le rouge du service coupé et le rouge du
  **compte verrouillé** ne sont jamais le même aplat ni côte à côte. Le verrou garde sa forme
  propre — **cadenas rouge plein** (`ck-keychip`) ; le service coupé se lit par une **bascule
  éteinte** (contour rouge, pas aplat plein). Forme et zone différentes : pas de confusion.
- **Bascules par opération + repli « avancé ».** Chaque service courant (Gmail, Drive, Calendar,
  Docs, Sheets, Tasks) affiche ses **opérations** en bascules (le grain de `default_policy.py`),
  pas un seul on/off par service. C'est ce qui rend **vraie** la promesse « aucune capacité
  perdue » : un compte « Gmail lire + brouillons oui, envoyer non » se réédite tel quel. Un pli
  **« avancé »** garde l'édition brute pour les scopes rares (Keep, spécifiques Workspace).

## Critères d'acceptation

- [ ] Sur la page d'un compte, **chaque opération** d'un service courant s'active/coupe d'un clic (grain de `gateway/default_policy.py`), **sans** ouvrir la modale Policy — aucune opération activée ou perdue en douce.
- [ ] Activer l'écriture Drive pose `zonesOnly` (jamais wildcard) ; `writeFolders` **vide** = défaut sûr (écriture refusée au niveau compte → chaque session demande son grant temporaire dans la vue Sessions) **ou** renseignée (zones permanentes). Jamais d'obligation de créer une zone permanente, et **aucun grant temporaire émis depuis la page compte**.
- [ ] La ligne Drive a un bouton « dossiers » éditant les **zones permanentes** (`writeFolders`) par une **mutation zone-seule** qui **préserve les flags d'opération** existants (pas `mag policy allow`, qui activerait `create`/`update` en douce) ; il **n'émet aucun grant temporaire** (jamais `/api/profiles/<alias>/grant`).
- [ ] Le texte long « Retirer ce compte… » est remplacé par un bouton + infobulle ; la modale de confirmation est conservée.
- [ ] La liste des comptes montre des vignettes d'état **colorées** : connecté = bleu, ouvert/permissif = vert, fermé/restreint = rouge. **Ce que comptent** ces vignettes (verrou compte vs compteur de sessions) suit la fiche [`0106`](0106-vue-compte-orientee-sessions.md) ; 0107 n'impose que le code couleur.
- [ ] Le bouton « Connecter un compte » est **sous** la liste.
- [ ] Rendu clair ET sombre corrects ; zéro dépendance ajoutée ; `./scripts/test.sh` au vert.

## Comment vérifier

Ouvrir un compte : activer puis couper une **opération** précise (ex. Gmail « envoyer ») et
vérifier que la policy suit au bon grain (`mag policy <alias> show`). Activer l'écriture Drive
**sans** créer de zone : vérifier que le mode zones est posé (`zonesOnly`) et qu'**aucun grant
compte-large** n'est émis — la page compte ne touche que `writeFolders` (permanent). Le grant
temporaire d'une écriture se fait **dans la vue Sessions** (`/api/sessions/<sid>/grant`). Revenir à
la liste : vérifier les vignettes colorées et le bouton « Connecter » en bas. Contrôler en clair et
en sombre.

## Routage des autres retours PO (2026-09-03)

Le reste du feedback de Thomas est **déjà couvert** ou **à replier dans une fiche existante** —
listé ici pour ne rien perdre au grooming.

**Déjà en backlog (rien à créer) :**
- Cliquer une ligne de session → page de config de la session : fiche [`0094`](0094-sessions-page-dediee-reactive.md) (page dédiée) + [`0098`](0098-micro-routeur-vues.md) (routeur).
- Tri + bascule liste/vignettes des sessions : fiche [`0099`](done/0099-sessions-pilote-tri-liste-vignettes.md).
- Nom lisible de session (au lieu de l'id) : fiche [`0101`](0101-nom-de-session-fourni-par-le-client.md). Id réservé à la page de session.
- Sessions par compte + bouton « voir les droits » : fiche [`0106`](0106-vue-compte-orientee-sessions.md).
- Journal d'accès sous la config d'une session : fiche [`0102`](done/0102-journal-page-monitoring-filtres-par-session.md) (journal par session).

**À replier au grooming des fiches concernées :**
- **Journal** → fiche [`0102`](done/0102-journal-page-monitoring-filtres-par-session.md) : pastille de couleur autour du **nom du compte** ; libeller les lignes **sans session** (élicitation / `mag`) au lieu d'un blanc ; **date sur une seule ligne** (colonne trop étroite / police trop grosse) ; **expansion de ligne** (une ligne par entrée, dépliable) façon outil de monitoring, avec **filtres + recherche + par date** et logs au bon format.
- **Mobile** → fiche [`0104`](done/0104-app-shell-responsive-mobile.md) : un **compte sur une seule ligne** (en retirant les libellés verrou/déverrou) ; les **3 vignettes sur une seule ligne** ; **retirer le chevron** de droite (la ligne est déjà cliquable).
- **En-tête** → fiche [`0103`](done/0103-refonte-barre-navigation-admin.md) : retirer le sous-titre « **admin local** » ; trancher le **nom produit** (« gma » / « multi-account ») ; **version sous le titre**, pas en bas ; la marque `◧` est un **glyphe bouche-trou**, pas un vrai logo (à concevoir : logo + favicon). L'**aide/Doc** doit s'ouvrir en **page plein écran**, pas en petite modale (même patron que Sessions/Journal).

## Hors périmètre

- Pas de nouveau modèle de droits : on édite la **policy** existante et on réutilise l'API zones.
- Le menu **hamburger** est écarté pour l'instant (choix PO : 3 destinations de pair, cf. 0104).
