---
id: 0107
title: Vue compte — piloter les droits sur place (remplacer la modale Policy) + nettoyer la liste
type: feature
priority: P1
product: google-mcp-multi-account
version:
epic: 0060
status: todo
ready: 2026-09-03
pr:
created: 2026-09-03
---

## En clair

Aujourd'hui, pour changer les droits d'un compte, il faut ouvrir la page **Policy** — austère
et à part. On veut l'inverse : **régler les droits directement sur la page du compte**. Chaque
service (Gmail, Drive…) devient un bouton qu'on active ou coupe d'un clic. Vert = autorisé,
rouge = coupé (au lieu du texte barré actuel). La ligne Drive gagne un bouton « dossiers » à
droite, pour choisir les zones d'écriture. Au passage, on nettoie la liste des comptes :
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
Chaque service devient un **bouton d'état cliquable** sur la page du compte. Un clic active
(vert) ou coupe (rouge). L'écriture Drive garde son garde-fou : l'activer ouvre le choix de
zones (pas de wildcard, cf. ADR-0007). La modale Policy disparaît, ou se replie en « mode
avancé » (édition JSON brute) pour les cas de bord.

**B. Bouton « dossiers » sur la ligne Drive.**
À droite de la ligne Drive, une icône ouvre la gestion des **zones d'écriture** (dossiers).
Réutilise le sélecteur existant (`openZones` `:2179`, navigateur de dossiers `afPick` `:3360`).

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
- **Bascules + repli « avancé ».** Les services courants (Gmail, Drive, Calendar, Docs, Sheets,
  Tasks) passent en **bascules**. Un pli **« avancé »** conserve l'édition brute pour les scopes
  rares (Keep, spécifiques Workspace). On ne perd **aucune** capacité de la modale Policy actuelle.

## Critères d'acceptation

- [ ] Sur la page d'un compte, chaque service s'active/coupe d'un clic, **sans** ouvrir la modale Policy.
- [ ] Activer l'écriture Drive **impose** de choisir au moins une zone (pas de wildcard).
- [ ] La ligne Drive a un bouton « dossiers » ouvrant la gestion des zones.
- [ ] Le texte long « Retirer ce compte… » est remplacé par un bouton + infobulle ; la modale de confirmation est conservée.
- [ ] La liste des comptes montre des vignettes d'état **colorées** : connecté = bleu, ouvert/permissif = vert, fermé/restreint = rouge. **Ce que comptent** ces vignettes (verrou compte vs compteur de sessions) suit la fiche [`0106`](0106-vue-compte-orientee-sessions.md) ; 0107 n'impose que le code couleur.
- [ ] Le bouton « Connecter un compte » est **sous** la liste.
- [ ] Rendu clair ET sombre corrects ; zéro dépendance ajoutée ; `./scripts/test.sh` au vert.

## Comment vérifier

Ouvrir un compte : activer puis couper Gmail et Drive d'un clic, et vérifier que la policy suit
(`mag policy <alias> show`). Activer l'écriture Drive : le choix de zone doit s'imposer. Revenir
à la liste : vérifier les 3 vignettes colorées et le bouton « Connecter » en bas. Contrôler en
clair et en sombre.

## Routage des autres retours PO (2026-09-03)

Le reste du feedback de Thomas est **déjà couvert** ou **à replier dans une fiche existante** —
listé ici pour ne rien perdre au grooming.

**Déjà en backlog (rien à créer) :**
- Cliquer une ligne de session → page de config de la session : fiche [`0094`](0094-sessions-page-dediee-reactive.md) (page dédiée) + [`0098`](0098-micro-routeur-vues.md) (routeur).
- Tri + bascule liste/vignettes des sessions : fiche [`0099`](0099-sessions-pilote-tri-liste-vignettes.md).
- Nom lisible de session (au lieu de l'id) : fiche [`0101`](0101-nom-de-session-fourni-par-le-client.md). Id réservé à la page de session.
- Sessions par compte + bouton « voir les droits » : fiche [`0106`](0106-vue-compte-orientee-sessions.md).
- Journal d'accès sous la config d'une session : fiche [`0102`](0102-journal-page-monitoring-filtres-par-session.md) (journal par session).

**À replier au grooming des fiches concernées :**
- **Journal** → fiche [`0102`](0102-journal-page-monitoring-filtres-par-session.md) : pastille de couleur autour du **nom du compte** ; libeller les lignes **sans session** (élicitation / `mag`) au lieu d'un blanc ; **date sur une seule ligne** (colonne trop étroite / police trop grosse) ; **expansion de ligne** (une ligne par entrée, dépliable) façon outil de monitoring, avec **filtres + recherche + par date** et logs au bon format.
- **Mobile** → fiche [`0104`](0104-app-shell-responsive-mobile.md) : un **compte sur une seule ligne** (en retirant les libellés verrou/déverrou) ; les **3 vignettes sur une seule ligne** ; **retirer le chevron** de droite (la ligne est déjà cliquable).
- **En-tête** → fiche [`0103`](0103-refonte-barre-navigation-admin.md) : retirer le sous-titre « **admin local** » ; trancher le **nom produit** (« gma » / « multi-account ») ; **version sous le titre**, pas en bas ; la marque `◧` est un **glyphe bouche-trou**, pas un vrai logo (à concevoir : logo + favicon). L'**aide/Doc** doit s'ouvrir en **page plein écran**, pas en petite modale (même patron que Sessions/Journal).

## Hors périmètre

- Pas de nouveau modèle de droits : on édite la **policy** existante et on réutilise l'API zones.
- Le menu **hamburger** est écarté pour l'instant (choix PO : 3 destinations de pair, cf. 0104).
