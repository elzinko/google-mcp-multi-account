---
id: 0008
title: Connexion dynamique d'un nouveau compte via élicitation forte (access_request kind=add_account)
type: feature
priority: P2
version:
epic:
status: shipped
ready:
pr: "#7"
created: 2026-07-22
---

## Contexte / Problème

Question de revue (2026-07-22) : un LLM peut-il, en cours de route, faire
connecter de **nouvelles adresses Gmail** (au-delà des comptes déjà présents),
dynamiquement et via élicitation à authentification forte ?

État actuel — le mécanisme existe mais n'est PAS de première classe :
- `mag add <alias> [email]` connecte un compte à tout moment (OAuth
  navigateur, vérifie l'email attendu, écrit une policy prudente). ✅
- MAIS : **pas gaté par strong auth** (Touch ID ne protège que unlock/grant ;
  ici la barrière humaine est le consentement OAuth dans le navigateur).
- **Pas d'outil d'élicitation** côté gateway/MCP : `access_request` n'a que
  les kinds `unlock` et `grant`. Le LLM ne peut donc que *suggérer* la
  commande shell `mag add`, sans flux dédié ni garde-fou.
- **Prérequis par nouveau compte non portés par le flux** : test-user (si app
  en Testing) + binding IAM `serviceUsageConsumer` (cf. 0005). Aujourd'hui à
  la charge de l'humain, sans rappel automatique.
- **Un seul projet GCP** : `MASTER_SECRET = ~/.config/gws-accounts/client_secret.json`
  est partagé par tous les profils. « Dans d'autres projets [GCP] » n'est
  PAS supporté — il faudrait un `client_secret.json` par profil/projet.

## Proposition

Faire de l'ajout de compte une élicitation de première classe, alignée sur
unlock/grant :

1. **`access_request` kind=`add_account`** (gateway + tool MCP) : le LLM
   décrit le besoin (alias souhaité, email cible) ; la gateway renvoie un
   message d'élicitation + la commande exacte `mag add <alias> <email>`
   (et, si nécessaire, la commande IAM de 0005). N'exécute jamais.
2. **Strong auth optionnelle sur `mag add`** : si `strongauth on`, exiger
   Touch ID avant de lancer le flux OAuth (cohérence avec unlock/grant).
3. **Enchaînement des prérequis** : après connexion, rappeler/vérifier le
   binding IAM (réutilise la sonde de 0005).
4. **(Étendu, à décider)** support multi-projet : `client_secret.json` par
   profil pour connecter des comptes rattachés à d'autres projets GCP.

## Critères d'acceptation

- [x] Un LLM peut déclencher l'élicitation « connecter un nouveau compte »
      via un tool (`access_request` kind=`add_account`, email requis), obtenir
      la commande exacte, et l'humain seul l'exécute. Vérifié hermétiquement :
      aucune création de profil, refus sans email, enum exposé dans le MCP.
- [x] `mag add` respecte `strongauth` (Touch ID) si activé — check placé
      après celui du client_secret (les envs de test n'atteignent jamais la
      boîte biométrique). Boîte réelle à constater au prochain `mag add`.
- [x] Le flux rappelle le binding IAM : message d'élicitation (status /
      sync-iam) + sonde post-connexion de `mag add` (0005) — pas de 403
      silencieux au 1er appel.
- [x] Décision multi-projet : **hors périmètre v1**. Un seul
      `client_secret.json` partagé (`MASTER_SECRET`) = un seul projet GCP par
      installation — suffisant pour l'usage perso visé ; un secret par profil
      (comptes d'autres projets GCP) rejoint la fiche 0003 (vault
      credentials), à re-trancher là-bas si le besoin devient réel.

## Notes

- Réutilise l'infra d'élicitation existante (`access_request`, messages
  suggérés) et la sonde IAM de 0005.
- Sécurité : l'ajout d'un compte élargit la surface — le geste humain
  (OAuth + éventuel Touch ID) reste la barrière ; le LLM ne fait que proposer.
- Lien : 0005 (chaîne d'onboarding), 0003 (vault credentials — un secret par
  profil rejoint la question multi-projet).
