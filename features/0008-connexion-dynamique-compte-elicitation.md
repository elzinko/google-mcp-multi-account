---
id: 0008
title: Connexion dynamique d'un nouveau compte via élicitation forte (access_request kind=add_account)
type: feature
priority: P2
version:
epic:
status: idea
ready:
pr:
created: 2026-07-22
---

## Contexte / Problème

Question de revue (2026-07-22) : un LLM peut-il, en cours de route, faire
connecter de **nouvelles adresses Gmail** (au-delà des comptes déjà présents),
dynamiquement et via élicitation à authentification forte ?

État actuel — le mécanisme existe mais n'est PAS de première classe :
- `gwsa add <alias> [email]` connecte un compte à tout moment (OAuth
  navigateur, vérifie l'email attendu, écrit une policy prudente). ✅
- MAIS : **pas gaté par strong auth** (Touch ID ne protège que unlock/grant ;
  ici la barrière humaine est le consentement OAuth dans le navigateur).
- **Pas d'outil d'élicitation** côté gateway/MCP : `access_request` n'a que
  les kinds `unlock` et `grant`. Le LLM ne peut donc que *suggérer* la
  commande shell `gwsa add`, sans flux dédié ni garde-fou.
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
   message d'élicitation + la commande exacte `gwsa add <alias> <email>`
   (et, si nécessaire, la commande IAM de 0005). N'exécute jamais.
2. **Strong auth optionnelle sur `gwsa add`** : si `strongauth on`, exiger
   Touch ID avant de lancer le flux OAuth (cohérence avec unlock/grant).
3. **Enchaînement des prérequis** : après connexion, rappeler/vérifier le
   binding IAM (réutilise la sonde de 0005).
4. **(Étendu, à décider)** support multi-projet : `client_secret.json` par
   profil pour connecter des comptes rattachés à d'autres projets GCP.

## Critères d'acceptation

- [ ] Un LLM peut déclencher l'élicitation « connecter un nouveau compte »
      via un tool, obtenir la commande exacte, et l'humain seul l'exécute.
- [ ] `gwsa add` respecte `strongauth` (Touch ID) si activé.
- [ ] Le flux rappelle le binding IAM (pas de 403 silencieux au 1er appel).
- [ ] Décision tracée sur le multi-projet (supporté ou explicitement hors
      périmètre v1, avec la raison).

## Notes

- Réutilise l'infra d'élicitation existante (`access_request`, messages
  suggérés) et la sonde IAM de 0005.
- Sécurité : l'ajout d'un compte élargit la surface — le geste humain
  (OAuth + éventuel Touch ID) reste la barrière ; le LLM ne fait que proposer.
- Lien : 0005 (chaîne d'onboarding), 0003 (vault credentials — un secret par
  profil rejoint la question multi-projet).
