---
id: 0036
title: Refonte des cartes profil de l'admin — liste, page de compte, zones (spec maquette v11)
type: feature
priority: P2
version:
epic:
status: shipped
ready: 2026-07-28
pr: "#44"
created: 2026-07-27
---

## Contexte / Problème

Revue UX démarrée sur une capture réelle (2026-07-27) : les cartes mélangeaient
connexion et accès, les badges d'états opposés se ressemblaient, « Révoquer »
dominait, le vocabulaire fuyait de la plomberie (« jeton »). Onze maquettes
itérées avec l'utilisateur, une revue adverse, une revue architecte
(ADR-0004, à réviser), un panel de nommage (lentilles novice / exactitude /
cohérence).

**La source de vérité visuelle et comportementale est la maquette
[docs/design/admin-cards-v11.html](../docs/design/admin-cards-v11.html)**
(v1→v10 conservées à côté pour l'historique des décisions).

## Spécification retenue (à implémenter dans `admin/index.html` + `server.js`)

### Modèle mental — deux commandes par compte, jamais mélangées

| Commande | Contrôle | États | Geste |
|---|---|---|---|
| **Connexion à Google** | interrupteur (toggle) | connecté / déconnecté (ligne grisée) | l'allumer = refaire la connexion (navigateur) |
| **Accès** (verrou) | cadenas cliquable | 🔒 fermé (rouge) / 🔓 ouvert (orange) + décompte | fermé→clic = Touch ID, 30 min ; ouvert→clic = confirmation puis reverrouille |

Interdits à l'écran : « jeton », « OAuth », « token ». Lexique retenu (les
mots vivent dans les infobulles et boutons ; à l'écran l'état est porté par
l'icône seule + « encore N:SS ») : « Déverrouiller (30 min)… / Reverrouiller
maintenant / Prolonger… / Retirer ce compte de l'outil ».
« Prolonger… » ajoute **30 min cumulées** à l'échéance courante. Décompte :
`encore M:SS` sous l'heure, `encore H h MM` au-delà.
On garde la famille « verrou » (le chat dit déjà « profil verrouillé » via les
refus MCP, le CLI dit lock/unlock, Touch ID aussi) — voir fiche 0039 pour
harmoniser les autres surfaces.

### Vue liste (une ligne par compte, créneaux fixes)

`[email cliquable = copie] [interrupteur] [cadenas + décompte] [Prolonger… si ouvert] [chevron]`

- Emplacements **fixes** : l'état et l'action ne changent jamais de place,
  seul leur contenu change.
- **Compte à rebours réel** (`encore M:SS`), rafraîchi chaque seconde ; à zéro
  l'accès se reverrouille tout seul (et l'UI le montre).
- Compte **déconnecté** : ligne grisée, interrupteur éteint, mention
  « Déconnecté » — pas de cadenas, pas de chevron, ligne non ouvrable.
  Seule exception assumée : la copie de l'email reste cliquable (inoffensif).
- Copie au clic (email) avec coche ✓ + message éphémère.

### Page de compte (liste → détail, pas d'accordéon — ADR-0004 à réviser)

- Ouverture par clic sur une ligne connectée ; « ‹ Comptes » revient. Pas de
  routeur : bascule de vue.
- En-tête : email + interrupteur + cadenas/décompte + boutons explicites
  (« Déverrouiller (30 min)… » ou « Prolonger… » + « Reverrouiller maintenant »).
- **Droits par application** : une ligne **par service déclaré dans la policy
  du profil** (`gateway/default_policy.py` en compte 7 : gmail, drive,
  calendar, docs, sheets, tasks, keep — la maquette n'en montre que 4 à titre
  d'échantillon), nom en couleur accent, capacités en **vert** (autorisé) /
  **rouge** (refusé, ex. « envoi » — non barré), bouton « Configurer… » par
  ligne. Aucune liste de zones dans cette vue.
- **Zone de danger** en pied : « Retirer ce compte de l'outil » + texte qui
  précise que rien n'est supprimé chez Google.

### Fenêtre « Zones d'écriture — Drive » (Configurer… de la ligne Drive)

- Deux temps dans la même modale : la **liste** des zones, puis l'**ajout**.
- Ligne de zone : `[📁] [nom seul — chemin complet en infobulle, clic = copie]
  [pastille P/T colorée, infobulle] [icône ↗ ouvrir dans Drive] [croix ✕ retirer]`.
- Emplacement d'ajout : bloc en **pointillés** au gabarit d'une zone, bouton
  « ＋ Ajouter une zone » à droite.
- Ajout : **navigateur du Drive** (fil d'Ariane + « ＋ Nouveau dossier ici »,
  reprend l'existant `afCrumbs`/`gws drive files list` + fiche 0038), dossier
  choisi annulable par croix, durées 1/2/4/8/24 h, avertissement rouge
  (fiche 0037 — texte fourni par le serveur, pas codé en dur), « Accorder »
  actif seulement une fois un dossier choisi. Ajouts multiples enchaînables.

### Contrat serveur & règles d'implémentation

- Le décompte réel exige que `server.js` expose **l'échéance du déverrouillage
  en timestamp** (pas une durée pré-formatée) : le front calcule et rafraîchit,
  et montre le reverrouillage automatique à zéro sans recharger.
- **Pas d'`onclick` inline interpolé** avec des données (emails, noms de
  dossiers) : une apostrophe casserait le handler. Construction DOM + listeners,
  ou échappement systématique.
- Le bouton explicite « Reverrouiller maintenant » (page du compte) agit
  directement ; seule l'icône cadenas de la liste demande confirmation.

## Critères d'acceptation

- [ ] La liste rend les 3 situations (déverrouillé+décompte, verrouillé,
      déconnecté grisé) aux emplacements fixes de la maquette v11.
- [ ] Cadenas cliquable : fermé→déverrouille (Touch ID via gwsa) ;
      ouvert→confirmation puis reverrouille ; décompte réel, reverrouillage
      auto à zéro visible sans recharger.
- [ ] Interrupteur : éteint sur compte déconnecté ; l'allumer lance la
      reconnexion ; l'éteindre est refusé avec renvoi vers la zone de danger.
- [ ] Page de compte : droits par appli en vert/rouge, « Configurer… » ouvre
      la fenêtre zones (Drive) ou l'éditeur de policy (autres).
- [ ] Fenêtre zones conforme (nom seul + infobulle chemin, P/T, ↗, ✕,
      pointillés, navigateur Drive avec création, ajouts multiples).
- [ ] Aucun « jeton / OAuth / token » dans l'UI.
- [ ] `./scripts/test.sh` vert.

## Notes

- Maquettes : `docs/design/admin-cards-v1..v11.html` — la v11 fait foi.
- Dépendances : [[0037-semantique-suppression-en-zone]] (texte d'avertissement
  serveur), [[0038-creer-dossier-zone-rapidement]] (création de dossier),
  [[0039-harmoniser-vocabulaire-jeton]] (autres surfaces), ADR-0004 (à réviser
  accordéon → liste/détail avant implémentation).
- Question ouverte pour l'implémentation : « Ouvrir dans Drive » avec le bon
  compte Google (`authuser` / profil navigateur) n'est pas garanti par une
  simple URL — à creuser.
