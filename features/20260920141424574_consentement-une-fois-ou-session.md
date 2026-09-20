---
id: "20260920141424574"
title: Consentement « une fois / pour la session » + mode réglable depuis l'admin (raffinement transactionnel)
type: feature
priority: P1
product: google-multi-account
version:
epic: 0082
status: in-progress
ready: 2026-09-20
pr:
created: 2026-09-20
---

## En clair

Le consentement transactionnel marche (livré, #149), mais le test manuel a montré qu'il
manque le geste clé, celui de Claude Code : au moment d'autoriser, pouvoir dire **« une
fois »** ou **« pour toute la session »**. Cette fiche l'ajoute, rend le **mode réglable
depuis l'admin**, et **retire les durées** là où elles n'ont rien à faire.

C'est le modèle « accepter une fois / accepter pour la session » de Claude Code, appliqué
**par périmètre** (un dossier, un compte), **sans limite de temps**.

## Contexte / problème

Le test manuel de #149 (gma-tx, vrais comptes) a validé le cœur : refus sans session,
double consentement (chat + Touch ID), lecture et écriture signées par acte. Mais il a
révélé trois écarts avec l'intention produit :

1. **Pas de choix « pour la session ».** En mode manuel, chaque action redemande un Touch
   ID — y compris répéter exactement la même (écrire dans le même dossier). Il manque
   l'option « accepte ce périmètre pour le reste de la session ».
2. **Des durées non voulues.** L'ancien déverrouillage `unlock` arme les écritures pour
   **60 minutes** — une durée, alors que le modèle transactionnel n'en veut pas. (À part :
   la session a un TTL d'inactivité de 8 h, hérité d'ADR-0007 — sain, mais à rendre
   réglable, pas constant.)
3. **Mode non réglable depuis l'admin.** Le mode se choisit par variable d'env / fichier ;
   il faut un sélecteur dans l'interface admin (comme le menu de modes de Claude Code).

## Proposition

Un **sélecteur de mode** (admin), à la Claude Code :

- **Manuel (défaut)** — **par action, AUCUN TTL**. Une demande acceptée = **une** action ;
  la même action ensuite redemande. À chaque « oui » (dans le chat, avant le Touch ID),
  deux choix :
  - **« une fois »** (défaut) → on re-signe la prochaine fois ;
  - **« pour la session »** → ce **périmètre exact** (service × opération × ressource, ex.
    `drive:create` sous le dossier X) est accepté jusqu'à la fin de la session, **sans
    durée**, et disparaît **avec la session**.
- **Auto (opt-in)** — Claude regroupe les **lectures** sous une **fenêtre de durée
  configurable** ; l'écriture reste signée par acte (cf. garde-fou partage).

**Garde-fou partage (sortant).** « Pour la session » couvre la **lecture** et l'**écriture
sur ses propres fichiers** (create/update/copy/upload). Le **partage Drive**
(`permissions create`/`delete`, qui expose une donnée à un tiers) reste **par acte à chaque
fois** — jamais « pour la session ». C'est le point où un accès qui traîne serait le plus
dangereux (cohérent avec « irréversible/sortant toujours signé »).

**Durées = réglages, pas constantes.** La fenêtre du mode auto et le TTL d'inactivité de
session deviennent configurables (env + admin). Le déverrouillage par minutes (`unlock`)
est **retiré** en transactionnel — remplacé par « pour la session ».

Sous le capot : réutilise les **capacités de session** (ADR-0007, `session_grant_capability`)
en leur **retirant la durée** (portée = vie de la session) et en ajoutant le choix
« une fois / session » à l'étape de consentement in-conversation (le chat porte déjà un
« oui » avant le Touch ID).

## Critères d'acceptation

- [ ] **Manuel = par action, zéro TTL** : une action acceptée « une fois » n'ouvre aucun
  droit au-delà d'elle-même ; la même action ensuite redemande — testé.
- [ ] **« pour la session »** : après acceptation « session » d'un périmètre, une action
  **du même périmètre** repasse **sans nouveau geste** ; un périmètre **différent**
  redemande — testé.
- [ ] La grâce « session » **meurt avec la session** (fermeture ou expiration), **sans
  limite de temps** propre — testé.
- [ ] **Partage** (`drive permissions create/delete`) : **toujours par acte**, jamais
  couvert par « pour la session » — testé.
- [ ] **Mode réglable depuis l'admin** (manuel / auto), persisté ; repli fail-closed sur
  manuel — testé.
- [ ] Durées **configurables** (fenêtre auto, TTL d'inactivité de session) ; **retrait** du
  déverrouillage par minutes en transactionnel — testé (non-régression flag OFF).
- [ ] `./scripts/test.sh` au vert.

## Comment vérifier

Test manuel (gma-tx, vrais comptes) : en manuel, demander deux écritures dans le **même
dossier** ; à la 1ʳᵉ, choisir « pour la session » → la 2ᵉ passe **sans Touch ID**. Écrire
dans un **autre** dossier → **redemande**. Tenter un **partage** → **redemande toujours**,
même après un « pour la session » sur ce compte. Depuis l'admin, basculer le mode et
vérifier l'effet. Rouvrir le lendemain → la session a expiré (TTL réglable), tout redemande.

## Notes

- Vient du test manuel de #149 (2026-09-20). Screenshot de référence : le menu de modes de
  Claude Code (Auto / Manuel / …).
- Décision partage tranchée sur reco (partage = toujours par acte) — rouvrir si Thomas veut
  l'inverse.
- Raffine [ADR-0012](../docs/adr/ADR-0012-consentement-transactionnel-propagation.md)
  (Zone 4) ; le champ read_leases et les capacités de session existent déjà.
