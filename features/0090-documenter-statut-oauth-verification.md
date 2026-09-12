---
id: 0090
title: Documenter et outiller le statut OAuth (warning « non vérifiée » + Testing→Production)
type: feature
priority: P3
version:
epic:
status: todo
ready:
pr:
created: 2026-08-29
---

## En clair

Au premier login OAuth, Google affiche deux choses qui **inquiètent** l'utilisateur : un
avertissement « application non vérifiée », et l'email du **compte développeur** du projet. Les
deux sont **normaux** ici (chaque personne crée sa propre app OAuth). Cette fiche **documente**
pourquoi, et outille le passage **Testing → Production** — qui supprime l'expiration des accès
au bout de 7 jours (la cause des reconnexions `mag add`).

## Contexte / Problème

Au premier login OAuth, Google affiche deux choses qui inquiètent l'utilisateur :

1. **« Google n'a pas validé cette application »** — écran d'avertissement, avec
   « Paramètres avancés → Accéder … (non sécurisé) ».
2. Le **compte développeur** du projet (ex. `mapetitecolocation@gmail.com`).

Ces deux points sont **normaux** dans le modèle du projet : **chaque utilisateur crée sa
propre app OAuth** (son projet GCP, son `client_secret`). L'email développeur affiché
n'est donc visible **que par l'utilisateur qui a créé le projet** — jamais par les autres
qui installeront le produit. Mais rien ne l'explique aujourd'hui : l'utilisateur croit à
un bug, à une fuite d'identité, ou à une appli douteuse.

Deux sujets connexes, à documenter (et outiller) :

- **Le warning « non vérifiée »** — pourquoi il apparaît, ce qu'impliquerait la
  vérification Google, et pourquoi on ne la vise **pas** en modèle local souverain.
- **Le statut Testing → Production** — en mode « Testing », les refresh tokens
  **expirent au bout de 7 jours** (cause des `exit code 2` → reconnexion `mag add`).
  Passer l'app en « Production », **même sans** vérification, supprime cette expiration.

## Proposition (à groomer)

- **Doc** dédiée (section de `docs/setup-oauth.md` ou page à part) qui explique :
  - le warning est **attendu** ; comment passer outre (Avancé → Continuer) ;
  - l'email développeur n'est vu **que par soi** (modèle par-utilisateur) ;
  - la vérification Google — la **revue est gratuite**, mais **deux niveaux** de scopes à
    ne pas confondre :
    - scopes **sensibles** → **vérification/revue de marque** (écran de consentement,
      politique de confidentialité, éventuelle vidéo démo) — **sans** audit tiers payant
      obligatoire ;
    - scopes **restreints** (Gmail, Drive complet — ceux qu'utilise le produit) → **en
      plus**, une **évaluation de sécurité annuelle par un tiers (type CASA)**, qui peut
      coûter cher ;
    - l'open source **n'exempte pas** → vérification non visée en local souverain ;
  - Testing → Production : bénéfice (fin de l'expiration 7 jours), limites éventuelles
    selon les scopes, gestes console.
- **Infobulle admin** : sur l'écran « Connecter un compte » (et/ou 🩺 Setup), une note
  courte « Pourquoi ce warning ? » qui renvoie à la doc.
- **Vérifier les faits** (coûts, seuils, niveaux de scopes, effet Production sur
  l'expiration) sur la doc Google **au moment du grooming/dev** — tarifs et quotas
  évoluent ; ne rien figer de chiffré sans source datée.

## Critères d'acceptation (à affiner)

- La doc explique warning + email dev + vérification (2 niveaux de scopes) + Testing→Production.
- L'admin affiche une note/infobulle « Pourquoi ce warning ? » liée à la doc.
- Aucune promesse chiffrée figée dans le code sans source datée.

## Comment vérifier

Lire la doc : elle explique le warning, l'email dev (visible que par soi), les deux niveaux de
vérification Google, et le passage Testing → Production. Depuis l'admin « Connecter un compte »,
l'infobulle « Pourquoi ce warning ? » renvoie à cette doc. Aucun chiffre (coût, seuil) n'est figé
dans le code sans source datée.

## Notes

- Regroupe **deux** demandes (warning/vérification et Testing→Production) : même écran,
  même doc → une seule fiche. Scinder au grooming si le volet « Production » (geste
  console + effet sur l'expiration 7 j, qui touche les `exit code 2`) mérite son propre lot.
- Ne change **pas** le modèle « une app par utilisateur » : pas d'app centrale à faire
  vérifier, donc pas de coût d'audit pour le mainteneur.
