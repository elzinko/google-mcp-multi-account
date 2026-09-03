---
id: 0106
title: Vue compte orientée sessions — compteur, liste des sessions et droits par session
type: feature
priority: P2
product: google-mcp-multi-account
version:
epic:
status: todo
ready: 2026-09-03
pr:
created: 2026-09-01
---

## En clair

Aujourd'hui la page **Comptes** affiche un état « déverrouillé / verrouillé » par compte.
C'est trompeur : depuis les droits-par-session, l'accès **dépend de chaque session**, pas du
compte en bloc. On veut rendre la vue compte **consciente des sessions** : combien de
sessions utilisent le compte, lesquelles, sous quel nom, et avec quels droits.

Fait suite aux remarques de Thomas (2026-09-01) sur la refonte Cockpit (PR #128). Ce sont
des évolutions **fonctionnelles**, distinctes de la refonte visuelle.

Références (chemins locaux) : [ADR-0007](../docs/adr/ADR-0007-droits-par-session.md) + fiche
[`0076`](done/0076-droits-par-session-phase-a.md) (droits propres par conversation), page
Sessions [`0094`](0094-sessions-page-dediee-reactive.md), page Journal
[`0102`](done/0102-journal-page-monitoring-filtres-par-session.md), nom de session
[`0101`](0101-nom-de-session-fourni-par-le-client.md).

## Contexte / problème

Le cadenas par compte (composant `ckKeychip`, page Comptes) reflète le **verrou admin
global** du compte — `mag lock/unlock`, la porte d'élicitation. Ce n'est pas faux, mais à
côté du modèle « un accès par session », ça brouille le message. On lit « verrouillé » comme
un état du compte, alors que la réalité est « telle session a débloqué, telle autre non ».

## Proposition

**A. Remplacer l'état binaire par un compteur de sessions (page Comptes).**
Par compte, un petit indicateur : nombre de sessions actives, dont X déverrouillées / Y
verrouillées. Plus honnête vis-à-vis du modèle par session.
→ *Tranché (grooming 2026-09-03)* : on **garde un mini-badge « porte d'élicitation : ouverte /
fermée »** à côté du compteur de sessions. Le verrou admin global (`mag lock/unlock`) reste une
info utile ; il devient **secondaire** (petit badge), pas supprimé.

> **Partage avec la fiche [`0107`](0107-vue-compte-droits-sur-place.md).** 0106 décide **ce que
> comptent** les vignettes d'état de la liste des comptes (ici : virer le « verrouillé /
> déverrouillé » trompeur au profit d'un compteur de sessions + porte d'élicitation). 0107 ne
> décide que leur **couleur** (connecté = bleu, ouvert = vert, fermé = rouge). Les deux composent ;
> sur la sémantique de l'état compte, **0106 prime**.

**C. Lister les sessions en cours par compte.**
Dans le détail d'un compte, la liste des sessions qui utilisent ce compte : id court, client,
activité, état. Réutilise les données de la page Sessions, filtrées par compte.

**D. Afficher le nom de la session (LLM) par session.**
Chaque session montre un nom lisible plutôt que son id brut. Dépend de la fiche `0101` (nom
fourni par le client) : si le client fournit déjà un nom, l'afficher ; sinon `0101` le livre.
Fallback : id court + client.

**E. Bouton « voir les droits » par session.**
Depuis une session (page Sessions et liste par compte), un bouton ouvre le détail de **tous
les droits accordés à cette session** pour ce compte : scopes, zones Drive, expiration.
Lecture seule ; réutilise la modale de droits en mode consultation.
→ *Grain selon l'API (grooming 2026-09-03)* : l'API admin `/api/sessions` n'expose pas encore
les droits **fins par service** d'une session. E affiche donc ce que l'API donne (scopes, zones
Drive, expiration) ; le grain par opération suivra l'exposition API. Dépendance notée, **non
bloquante** pour A / C / D.

## Critères d'acceptation

- [ ] Page Comptes : plus d'état verrouillé/déverrouillé trompeur ; un compteur de sessions par compte (déverrouillées / verrouillées).
- [ ] Détail compte : liste des sessions en cours utilisant ce compte.
- [ ] Chaque session affiche un nom lisible (ou fallback id court + client).
- [ ] Chaque session a un bouton « voir les droits » ouvrant le détail des droits accordés.
- [ ] Lecture seule ; clair ET sombre ; zéro dépendance ajoutée ; `./scripts/test.sh` au vert.

## Comment vérifier

Ouvrir l'admin, page Comptes : vérifier le compteur de sessions par compte. Ouvrir un
compte : voir la liste des sessions, chacune avec son nom et un bouton « voir les droits ».
Cliquer : le détail des droits de la session s'affiche. Vérifier clair et sombre.

## Hors périmètre (déjà traité)

Le survol peu visible du bouton « Connecter » était un bug de la refonte : la règle générale
de survol repeignait le fond des boutons pleins en gris. **Corrigé dans la PR #128** (boutons
primaire et danger), pas besoin de fiche.
