---
id: "20261013102010760"
title: Provisioning GCP assisté par navigateur, piloté par le LLM (un geste, pauses humaines explicites)
type: feature
priority: P2
version:
epic:
status: idea
ready:
pr:
created: 2026-10-13
---

## En clair

Aujourd'hui, créer le projet GCP demande des allers-retours console que l'humain
fait à la main — et c'est là qu'on se trompe (mauvais compte actif, étape
oubliée). L'idée : **une commande qui lance tout le provisioning « assisté
navigateur »**, où le LLM pilote la console GCP dans un navigateur pour les
étapes automatisables, et **marque un STOP clair** aux rares étapes qui restent
des gestes humains obligatoires. But : que l'utilisateur n'ait plus à savoir où
cliquer — le LLM l'accompagne du début à la fin.

## Contexte / Problème

Le provisioning GCP mélange trois natures d'étapes :

1. **Automatisable sans navigateur** (déjà fait par `provision-gcp.sh`) : créer
   le projet, activer les APIs, l'écran de consentement (best-effort API).
2. **Automatisable AU navigateur** mais pas en API : certaines pages console.
3. **Geste humain obligatoire**, non délégable :
   - le **login gcloud** (identifiants — jamais le LLM) ;
   - la **création du client OAuth « Desktop »** et la **publication en
     Production** — Google a **fermé les APIs** correspondantes
     (voir [`../docs/setup-oauth.md`](../docs/setup-oauth.md)).

Sans accompagnement, l'humain se perd dans ces étapes. Symptôme réel
(session 2026-10-13) : bloqué à « Publier en Production » parce que le **mauvais
compte Google** était actif dans la console — le projet appartenait à un autre
compte que celui ouvert dans le navigateur. Rien ne l'avait signalé.

## Proposition

Un **mode « provisioning assisté navigateur »** — une commande (ou une
instruction documentée que le LLM suit) qui enchaîne le provisioning en pilotant
un navigateur (Claude in Chrome / browser pane), avec les **pauses humaines
explicitées** :

- Le LLM fait au navigateur ce qui est automatisable (naviguer, lire la page,
  cliquer les boutons sûrs, **vérifier le compte actif** avant d'agir).
- À chaque **geste humain obligatoire**, il **s'arrête** et dit précisément quoi
  faire (ex. « connecte-toi avec tel compte », « clique Download JSON »,
  « clique Publish → Confirm »), puis **reprend** après.
- **Garde-fou compte** : avant toute action console, vérifier que le compte
  actif dans le navigateur == le propriétaire du projet (`gcloud` actif), et
  **refuser/alerter** sinon (le piège de la session 2026-10-13).

Où vivent les instructions : à préciser au grooming — soit un bloc dans
[`../docs/setup-oauth.md`](../docs/setup-oauth.md), soit une entrée dédiée que
`provision-gcp.sh` ou un nouveau mode référence.

**Frontière à respecter (doctrine du projet)** : le LLM **ne fait jamais** le
login/credentials ni ne contourne un STOP humain. Il **assiste**, il ne
**remplace** pas le consentement humain.

## Critères d'acceptation

- [ ] Le LLM peut dérouler le provisioning en pilotant un navigateur, avec un
      point d'entrée unique (commande ou instruction documentée).
- [ ] Chaque étape **geste humain obligatoire** est nommée, avec un STOP explicite
      (login gcloud, client OAuth Desktop, publication) — et le flux **reprend** après.
- [ ] **Vérification du compte actif** avant toute action console ; alerte claire
      si le compte du navigateur ≠ propriétaire du projet.
- [ ] La doc distingue noir sur blanc : *automatisable par le LLM* vs *geste humain*.
- [ ] Aucune régression de doctrine : pas de login/credentials par le LLM, pas de
      contournement de STOP.

## Comment vérifier

- Dérouler le mode sur un projet neuf : le LLM crée/active/configure au
  navigateur, s'arrête aux 3 gestes humains, et reprend — provisioning complet au
  bout.
- Rejouer avec le **mauvais compte** actif dans le navigateur : le garde-fou doit
  **alerter et refuser** d'agir (reproduit le blocage du 2026-10-13).
- Relire la doc : un nouveau venu comprend sans lire le code ce que le LLM fait
  seul et ce qu'il doit faire lui-même.

## Notes

- **Fiches liées** (à regrouper éventuellement au grooming) :
  - [`0090`](0090-documenter-statut-oauth-verification.md) — statut OAuth,
    Testing→Production : recoupe l'étape « publier ».
  - [`0089`](0089-choix-profil-navigateur-oauth-add.md) — choix du profil
    navigateur à l'ouverture OAuth : même surface « navigateur + compte ».
  - [`0007`](done/0007-provisioning-idempotent-declaratif.md) — provisioning
    idempotent / Terraform (**shipped**) : la base CLI sur laquelle ce mode
    s'appuie.
- **Décision cadre** : CLI gcloud maintenant, Terraform plus tard (voir la PR
  https://github.com/elzinko/google-mcp-multi-account/pull/164). Terraform ne
  lèverait pas le mur OAuth : les mêmes 2-3 étapes resteraient manuelles quel que
  soit l'outil.
- **Mur API OAuth** : Google n'expose aucune API pour créer un client OAuth
  « Desktop » ni publier — ces étapes resteront des gestes humains au navigateur.

> Origine : session 2026-10-13 — publication manuelle bloquée par un mauvais
> compte actif dans la console. Idée capturée en `idea` (direction, pas encore
> groomée). Priorité P2 proposée, à confirmer par le PO.
